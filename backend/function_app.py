import json
import logging
import os
import base64

import azure.functions as func

from utils import auth_utils, cosmos_db, blob_storage, cognitive

app = func.FunctionApp(http_auth_level=func.AuthLevel.ANONYMOUS)

FRONTEND_URL = os.environ.get("FRONTEND_URL", "*")

# ── Helpers ───────────────────────────────────────────────────────────────────

def cors_headers() -> dict:
    return {
        "Access-Control-Allow-Origin": FRONTEND_URL,
        "Access-Control-Allow-Methods": "GET, POST, PUT, DELETE, OPTIONS",
        "Access-Control-Allow-Headers": "Content-Type, Authorization",
        "Content-Type": "application/json",
    }


def json_ok(data, status=200) -> func.HttpResponse:
    return func.HttpResponse(
        json.dumps(data, default=str),
        status_code=status,
        headers=cors_headers(),
    )


def json_err(msg: str, status=400) -> func.HttpResponse:
    return func.HttpResponse(
        json.dumps({"error": msg}),
        status_code=status,
        headers=cors_headers(),
    )


def preflight() -> func.HttpResponse:
    return func.HttpResponse("", status_code=204, headers=cors_headers())


# ── Auth Endpoints ────────────────────────────────────────────────────────────

@app.route(route="auth/register", methods=["POST", "OPTIONS"])
def register(req: func.HttpRequest) -> func.HttpResponse:
    if req.method == "OPTIONS":
        return preflight()
    try:
        body = req.get_json()
    except Exception:
        return json_err("Invalid JSON body")

    username = (body.get("username") or "").strip()
    email = (body.get("email") or "").strip().lower()
    password = body.get("password") or ""
    role = body.get("role") or "consumer"

    if not username or not email or not password:
        return json_err("username, email, and password are required")
    if role not in ("consumer",):
        # Creators are added by admin only — no self-registration
        return json_err("Public registration is for consumer accounts only")
    if len(password) < 6:
        return json_err("Password must be at least 6 characters")

    cosmos_db.ensure_containers()

    if cosmos_db.get_user_by_email(email):
        return json_err("Email already registered", 409)
    if cosmos_db.get_user_by_username(username):
        return json_err("Username already taken", 409)

    pw_hash = auth_utils.hash_password(password)
    user = cosmos_db.create_user(username, email, pw_hash, role)
    token = auth_utils.create_token(user["id"], user["username"], user["role"])

    return json_ok({
        "token": token,
        "user": {"id": user["id"], "username": user["username"], "role": user["role"]},
    }, 201)


@app.route(route="auth/login", methods=["POST", "OPTIONS"])
def login(req: func.HttpRequest) -> func.HttpResponse:
    if req.method == "OPTIONS":
        return preflight()
    try:
        body = req.get_json()
    except Exception:
        return json_err("Invalid JSON body")

    email = (body.get("email") or "").strip().lower()
    password = body.get("password") or ""

    if not email or not password:
        return json_err("email and password are required")

    cosmos_db.ensure_containers()
    user = cosmos_db.get_user_by_email(email)
    if not user or not auth_utils.verify_password(password, user["password_hash"]):
        return json_err("Invalid credentials", 401)

    token = auth_utils.create_token(user["id"], user["username"], user["role"])
    return json_ok({
        "token": token,
        "user": {"id": user["id"], "username": user["username"], "role": user["role"]},
    })


@app.route(route="auth/create-creator", methods=["POST", "OPTIONS"])
def create_creator(req: func.HttpRequest) -> func.HttpResponse:
    """Admin-only endpoint to create creator accounts (no public UI)."""
    if req.method == "OPTIONS":
        return preflight()

    # Protected by a simple admin secret header
    admin_secret = req.headers.get("X-Admin-Secret", "")
    if admin_secret != os.environ.get("ADMIN_SECRET", "changeme"):
        return json_err("Forbidden", 403)

    try:
        body = req.get_json()
    except Exception:
        return json_err("Invalid JSON body")

    username = (body.get("username") or "").strip()
    email = (body.get("email") or "").strip().lower()
    password = body.get("password") or ""

    if not username or not email or not password:
        return json_err("username, email, and password are required")

    cosmos_db.ensure_containers()
    if cosmos_db.get_user_by_email(email):
        return json_err("Email already registered", 409)

    pw_hash = auth_utils.hash_password(password)
    user = cosmos_db.create_user(username, email, pw_hash, "creator")
    return json_ok({"id": user["id"], "username": user["username"], "role": "creator"}, 201)


# ── Photo Endpoints ───────────────────────────────────────────────────────────

@app.route(route="photos", methods=["GET", "POST", "OPTIONS"])
def photos(req: func.HttpRequest) -> func.HttpResponse:
    if req.method == "OPTIONS":
        return preflight()

    if req.method == "GET":
        try:
            limit = int(req.params.get("limit", 20))
            offset = int(req.params.get("offset", 0))
        except ValueError:
            return json_err("limit and offset must be integers")
        cosmos_db.ensure_containers()
        items = cosmos_db.get_photos(limit=min(limit, 50), offset=offset)
        return json_ok({"photos": items, "count": len(items)})

    # POST — creator only
    claims, err = auth_utils.require_auth(req, role="creator")
    if err:
        return json_err(err, 401 if "Unauthorized" in err else 403)

    # Multipart form: fields + file
    try:
        title = req.form.get("title", "").strip()
        caption = req.form.get("caption", "").strip()
        location = req.form.get("location", "").strip()
        people_raw = req.form.get("people", "")
        people = [p.strip() for p in people_raw.split(",") if p.strip()]
        image_data_b64 = req.form.get("image_data", "")
        filename = req.form.get("filename", "photo.jpg")
        content_type = req.form.get("content_type", "image/jpeg")
    except Exception:
        return json_err("Failed to parse form data")

    if not title:
        return json_err("title is required")
    if not image_data_b64:
        return json_err("image_data (base64) is required")

    try:
        image_bytes = base64.b64decode(image_data_b64)
    except Exception:
        return json_err("Invalid base64 image data")

    # AI analysis — Computer Vision (Advanced Feature 1)
    ai_result = cognitive.analyze_image(image_bytes)

    # Upload to Blob Storage
    blob_url = blob_storage.upload_photo(image_bytes, content_type, filename)

    cosmos_db.ensure_containers()
    photo = cosmos_db.create_photo(
        creator_id=claims["sub"],
        creator_name=claims["username"],
        title=title,
        caption=caption,
        location=location,
        people=people,
        blob_url=blob_url,
        ai_tags=ai_result["tags"],
        ai_description=ai_result["description"],
    )
    return json_ok(photo, 201)


@app.route(route="photos/search", methods=["GET", "OPTIONS"])
def search_photos(req: func.HttpRequest) -> func.HttpResponse:
    if req.method == "OPTIONS":
        return preflight()
    q = req.params.get("q", "").strip()
    if not q:
        return json_err("q parameter is required")
    cosmos_db.ensure_containers()
    results = cosmos_db.search_photos(q)
    return json_ok({"photos": results, "count": len(results), "query": q})


@app.route(route="photos/my", methods=["GET", "OPTIONS"])
def my_photos(req: func.HttpRequest) -> func.HttpResponse:
    if req.method == "OPTIONS":
        return preflight()
    claims, err = auth_utils.require_auth(req, role="creator")
    if err:
        return json_err(err, 401 if "Unauthorized" in err else 403)
    cosmos_db.ensure_containers()
    items = cosmos_db.get_photos_by_creator(claims["sub"])
    return json_ok({"photos": items, "count": len(items)})


@app.route(route="photos/{photo_id}", methods=["GET", "DELETE", "OPTIONS"])
def photo_detail(req: func.HttpRequest, photo_id: str) -> func.HttpResponse:
    if req.method == "OPTIONS":
        return preflight()

    cosmos_db.ensure_containers()

    if req.method == "GET":
        photo = cosmos_db.get_photo_by_id(photo_id)
        if not photo:
            return json_err("Photo not found", 404)
        return json_ok(photo)

    # DELETE — creator who owns the photo
    claims, err = auth_utils.require_auth(req, role="creator")
    if err:
        return json_err(err, 401 if "Unauthorized" in err else 403)

    photo = cosmos_db.get_photo_by_id(photo_id)
    if not photo:
        return json_err("Photo not found", 404)
    if photo["creator_id"] != claims["sub"]:
        return json_err("You can only delete your own photos", 403)

    blob_storage.delete_photo(photo["blob_url"])
    cosmos_db.delete_photo(photo_id)
    return json_ok({"message": "Photo deleted"})


# ── Comment Endpoints ─────────────────────────────────────────────────────────

@app.route(route="photos/{photo_id}/comments", methods=["GET", "POST", "OPTIONS"])
def comments(req: func.HttpRequest, photo_id: str) -> func.HttpResponse:
    if req.method == "OPTIONS":
        return preflight()

    cosmos_db.ensure_containers()

    if req.method == "GET":
        items = cosmos_db.get_comments(photo_id)
        return json_ok({"comments": items, "count": len(items)})

    # POST — any authenticated user
    claims, err = auth_utils.require_auth(req)
    if err:
        return json_err(err, 401)

    try:
        body = req.get_json()
    except Exception:
        return json_err("Invalid JSON body")

    text = (body.get("text") or "").strip()
    if not text:
        return json_err("text is required")
    if len(text) > 500:
        return json_err("Comment too long (max 500 characters)")

    photo = cosmos_db.get_photo_by_id(photo_id)
    if not photo:
        return json_err("Photo not found", 404)

    # Sentiment analysis — Advanced Feature 2
    sentiment_result = cognitive.analyze_sentiment(text)

    comment = cosmos_db.create_comment(
        photo_id=photo_id,
        user_id=claims["sub"],
        username=claims["username"],
        text=text,
        sentiment=sentiment_result["sentiment"],
        sentiment_score=sentiment_result["score"],
    )
    return json_ok(comment, 201)


# ── Rating Endpoints ──────────────────────────────────────────────────────────

@app.route(route="photos/{photo_id}/rate", methods=["POST", "OPTIONS"])
def rate_photo(req: func.HttpRequest, photo_id: str) -> func.HttpResponse:
    if req.method == "OPTIONS":
        return preflight()

    claims, err = auth_utils.require_auth(req)
    if err:
        return json_err(err, 401)

    try:
        body = req.get_json()
    except Exception:
        return json_err("Invalid JSON body")

    rating = body.get("rating")
    if rating is None or not isinstance(rating, int) or not (1 <= rating <= 5):
        return json_err("rating must be an integer between 1 and 5")

    cosmos_db.ensure_containers()
    photo = cosmos_db.get_photo_by_id(photo_id)
    if not photo:
        return json_err("Photo not found", 404)

    record = cosmos_db.upsert_rating(photo_id, claims["sub"], rating)
    updated = cosmos_db.get_photo_by_id(photo_id)
    return json_ok({
        "rating": record,
        "photo_average": updated["average_rating"],
        "rating_count": updated["rating_count"],
    })


# ── Health Check ──────────────────────────────────────────────────────────────

@app.route(route="health", methods=["GET", "OPTIONS"])
def health(req: func.HttpRequest) -> func.HttpResponse:
    if req.method == "OPTIONS":
        return preflight()
    return json_ok({"status": "healthy", "service": "PhotoShare API"})
