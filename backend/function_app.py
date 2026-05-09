import json
import os
import sys
import traceback

import azure.functions as func

app = func.FunctionApp(http_auth_level=func.AuthLevel.ANONYMOUS)

_errors = []

try:
    from utils import auth_utils, cosmos_db, blob_storage, cognitive
except Exception:
    _errors.append(traceback.format_exc())

FRONTEND_URL = os.environ.get("FRONTEND_URL", "*")


def _h():
    return {"Content-Type": "application/json", "Access-Control-Allow-Origin": FRONTEND_URL,
            "Access-Control-Allow-Methods": "GET, POST, PUT, DELETE, OPTIONS",
            "Access-Control-Allow-Headers": "Content-Type, Authorization"}


def _ok(data, status=200):
    return func.HttpResponse(json.dumps(data, default=str), status_code=status, headers=_h())


def _err(msg, status=400):
    return func.HttpResponse(json.dumps({"error": msg}), status_code=status, headers=_h())


@app.route(route="health", methods=["GET"])
def health(req: func.HttpRequest) -> func.HttpResponse:
    return _ok({"status": "healthy", "load_errors": _errors})


@app.route(route="auth/register", methods=["POST"])
def register(req: func.HttpRequest) -> func.HttpResponse:
    try:
        body = req.get_json()
    except Exception:
        return _err("Invalid JSON")
    username = (body.get("username") or "").strip()
    email = (body.get("email") or "").strip().lower()
    password = body.get("password") or ""
    role = (body.get("role") or "consumer").strip().lower()
    if role not in ("consumer", "creator"):
        role = "consumer"
    if not username or not email or not password:
        return _err("username, email and password required")
    if len(password) < 6:
        return _err("Password must be at least 6 chars")
    cosmos_db.ensure_containers()
    if cosmos_db.get_user_by_email(email):
        return _err("Email already registered", 409)
    if cosmos_db.get_user_by_username(username):
        return _err("Username taken", 409)
    pw_hash = auth_utils.hash_password(password)
    user = cosmos_db.create_user(username, email, pw_hash, role)
    token = auth_utils.create_token(user["id"], user["username"], user["role"])
    return _ok({"token": token, "user": {"id": user["id"], "username": user["username"], "role": user["role"]}}, 201)


@app.route(route="auth/login", methods=["POST"])
def login(req: func.HttpRequest) -> func.HttpResponse:
    try:
        body = req.get_json()
    except Exception:
        return _err("Invalid JSON")
    email = (body.get("email") or "").strip().lower()
    password = body.get("password") or ""
    if not email or not password:
        return _err("email and password required")
    cosmos_db.ensure_containers()
    user = cosmos_db.get_user_by_email(email)
    if not user or not auth_utils.verify_password(password, user["password_hash"]):
        return _err("Invalid credentials", 401)
    token = auth_utils.create_token(user["id"], user["username"], user["role"])
    return _ok({"token": token, "user": {"id": user["id"], "username": user["username"], "role": user["role"]}})


@app.route(route="auth/create-creator", methods=["POST"])
def create_creator(req: func.HttpRequest) -> func.HttpResponse:
    if req.headers.get("X-Admin-Secret", "") != os.environ.get("ADMIN_SECRET", "changeme"):
        return _err("Forbidden", 403)
    try:
        body = req.get_json()
    except Exception:
        return _err("Invalid JSON")
    username = (body.get("username") or "").strip()
    email = (body.get("email") or "").strip().lower()
    password = body.get("password") or ""
    if not username or not email or not password:
        return _err("username, email and password required")
    cosmos_db.ensure_containers()
    if cosmos_db.get_user_by_email(email):
        return _err("Email already registered", 409)
    pw_hash = auth_utils.hash_password(password)
    user = cosmos_db.create_user(username, email, pw_hash, "creator")
    return _ok({"id": user["id"], "username": user["username"], "role": "creator"}, 201)


@app.route(route="photos", methods=["GET", "POST"])
def photos(req: func.HttpRequest) -> func.HttpResponse:
    if req.method == "GET":
        try:
            limit = int(req.params.get("limit", 20))
            offset = int(req.params.get("offset", 0))
        except ValueError:
            return _err("limit and offset must be integers")
        cosmos_db.ensure_containers()
        items = cosmos_db.get_photos(limit=min(limit, 50), offset=offset)
        return _ok({"photos": items, "count": len(items)})
    claims, err = auth_utils.require_auth(req, role="creator")
    if err:
        return _err(err, 401 if "Unauthorized" in err else 403)
    try:
        title = req.form.get("title", "").strip()
        caption = req.form.get("caption", "").strip()
        location = req.form.get("location", "").strip()
        people = [p.strip() for p in (req.form.get("people", "") or "").split(",") if p.strip()]
        image_data_b64 = req.form.get("image_data", "")
        filename = req.form.get("filename", "photo.jpg")
        content_type = req.form.get("content_type", "image/jpeg")
    except Exception:
        return _err("Failed to parse form data")
    if not title or not image_data_b64:
        return _err("title and image_data required")
    import base64 as b64
    try:
        image_bytes = b64.b64decode(image_data_b64)
    except Exception:
        return _err("Invalid base64")
    ai_result = cognitive.analyze_image(image_bytes)
    blob_url = blob_storage.upload_photo(image_bytes, content_type, filename)
    cosmos_db.ensure_containers()
    photo = cosmos_db.create_photo(
        creator_id=claims["sub"], creator_name=claims["username"],
        title=title, caption=caption, location=location, people=people,
        blob_url=blob_url, ai_tags=ai_result["tags"], ai_description=ai_result["description"])
    return _ok(photo, 201)


@app.route(route="photos/search", methods=["GET"])
def search_photos(req: func.HttpRequest) -> func.HttpResponse:
    q = req.params.get("q", "").strip()
    if not q:
        return _err("q required")
    cosmos_db.ensure_containers()
    results = cosmos_db.search_photos(q)
    return _ok({"photos": results, "count": len(results), "query": q})


@app.route(route="photos/my", methods=["GET"])
def my_photos(req: func.HttpRequest) -> func.HttpResponse:
    claims, err = auth_utils.require_auth(req, role="creator")
    if err:
        return _err(err, 401 if "Unauthorized" in err else 403)
    cosmos_db.ensure_containers()
    items = cosmos_db.get_photos_by_creator(claims["sub"])
    return _ok({"photos": items, "count": len(items)})


@app.route(route="photos/{photo_id}", methods=["GET", "DELETE"])
def photo_detail(req: func.HttpRequest) -> func.HttpResponse:
    photo_id = req.route_params.get("photo_id")
    cosmos_db.ensure_containers()
    if req.method == "GET":
        photo = cosmos_db.get_photo_by_id(photo_id)
        if not photo:
            return _err("Not found", 404)
        return _ok(photo)
    claims, err = auth_utils.require_auth(req, role="creator")
    if err:
        return _err(err, 401 if "Unauthorized" in err else 403)
    photo = cosmos_db.get_photo_by_id(photo_id)
    if not photo:
        return _err("Not found", 404)
    if photo["creator_id"] != claims["sub"]:
        return _err("Forbidden", 403)
    blob_storage.delete_photo(photo["blob_url"])
    cosmos_db.delete_photo(photo_id)
    return _ok({"message": "deleted"})


@app.route(route="photos/{photo_id}/comments", methods=["GET", "POST"])
def comments(req: func.HttpRequest) -> func.HttpResponse:
    photo_id = req.route_params.get("photo_id")
    cosmos_db.ensure_containers()
    if req.method == "GET":
        items = cosmos_db.get_comments(photo_id)
        return _ok({"comments": items, "count": len(items)})
    claims, err = auth_utils.require_auth(req)
    if err:
        return _err(err, 401)
    try:
        body = req.get_json()
    except Exception:
        return _err("Invalid JSON")
    text = (body.get("text") or "").strip()
    if not text or len(text) > 500:
        return _err("text required, max 500 chars")
    photo = cosmos_db.get_photo_by_id(photo_id)
    if not photo:
        return _err("Photo not found", 404)
    sentiment = cognitive.analyze_sentiment(text)
    comment = cosmos_db.create_comment(
        photo_id=photo_id, user_id=claims["sub"], username=claims["username"],
        text=text, sentiment=sentiment["sentiment"], sentiment_score=sentiment["score"])
    return _ok(comment, 201)


@app.route(route="photos/{photo_id}/rate", methods=["POST"])
def rate_photo(req: func.HttpRequest) -> func.HttpResponse:
    photo_id = req.route_params.get("photo_id")
    claims, err = auth_utils.require_auth(req)
    if err:
        return _err(err, 401)
    try:
        body = req.get_json()
    except Exception:
        return _err("Invalid JSON")
    rating = body.get("rating")
    if rating is None or not isinstance(rating, int) or not (1 <= rating <= 5):
        return _err("rating must be int 1-5")
    cosmos_db.ensure_containers()
    photo = cosmos_db.get_photo_by_id(photo_id)
    if not photo:
        return _err("Not found", 404)
    record = cosmos_db.upsert_rating(photo_id, claims["sub"], rating)
    updated = cosmos_db.get_photo_by_id(photo_id)
    return _ok({"rating": record, "photo_average": updated["average_rating"], "rating_count": updated["rating_count"]})
