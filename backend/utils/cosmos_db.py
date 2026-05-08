import os
import uuid
from datetime import datetime, timezone
from azure.cosmos import CosmosClient, PartitionKey, exceptions

_client = None
_db = None


def _get_db():
    global _client, _db
    if _db is None:
        _client = CosmosClient(
            os.environ["COSMOS_ENDPOINT"],
            credential=os.environ["COSMOS_KEY"],
        )
        _db = _client.get_database_client(os.environ.get("COSMOS_DATABASE", "photoshare"))
    return _db


def _container(name: str):
    return _get_db().get_container_client(name)


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


# ── Users ─────────────────────────────────────────────────────────────────────

def create_user(username: str, email: str, password_hash: str, role: str) -> dict:
    user = {
        "id": str(uuid.uuid4()),
        "username": username,
        "email": email,
        "password_hash": password_hash,
        "role": role,
        "created_at": now_iso(),
    }
    _container("users").create_item(user)
    return user


def get_user_by_email(email: str) -> dict | None:
    query = "SELECT * FROM c WHERE c.email = @email"
    items = list(_container("users").query_items(
        query=query,
        parameters=[{"name": "@email", "value": email}],
        enable_cross_partition_query=True,
    ))
    return items[0] if items else None


def get_user_by_username(username: str) -> dict | None:
    query = "SELECT * FROM c WHERE c.username = @u"
    items = list(_container("users").query_items(
        query=query,
        parameters=[{"name": "@u", "value": username}],
        enable_cross_partition_query=True,
    ))
    return items[0] if items else None


# ── Photos ────────────────────────────────────────────────────────────────────

def create_photo(creator_id: str, creator_name: str, title: str, caption: str,
                 location: str, people: list, blob_url: str,
                 ai_tags: list, ai_description: str) -> dict:
    photo = {
        "id": str(uuid.uuid4()),
        "creator_id": creator_id,
        "creator_name": creator_name,
        "title": title,
        "caption": caption,
        "location": location,
        "people": people,
        "blob_url": blob_url,
        "ai_tags": ai_tags,
        "ai_description": ai_description,
        "average_rating": 0.0,
        "rating_count": 0,
        "comment_count": 0,
        "created_at": now_iso(),
    }
    _container("photos").create_item(photo)
    return photo


def get_photos(limit: int = 20, offset: int = 0) -> list:
    query = f"SELECT * FROM c ORDER BY c.created_at DESC OFFSET {offset} LIMIT {limit}"
    return list(_container("photos").query_items(
        query=query, enable_cross_partition_query=True
    ))


def get_photo_by_id(photo_id: str) -> dict | None:
    try:
        return _container("photos").read_item(photo_id, partition_key=photo_id)
    except exceptions.CosmosResourceNotFoundError:
        return None


def search_photos(q: str) -> list:
    query = """
        SELECT * FROM c WHERE
        CONTAINS(LOWER(c.title), @q) OR
        CONTAINS(LOWER(c.caption), @q) OR
        CONTAINS(LOWER(c.location), @q) OR
        CONTAINS(LOWER(c.creator_name), @q)
        ORDER BY c.created_at DESC
    """
    return list(_container("photos").query_items(
        query=query,
        parameters=[{"name": "@q", "value": q.lower()}],
        enable_cross_partition_query=True,
    ))


def get_photos_by_creator(creator_id: str) -> list:
    query = "SELECT * FROM c WHERE c.creator_id = @cid ORDER BY c.created_at DESC"
    return list(_container("photos").query_items(
        query=query,
        parameters=[{"name": "@cid", "value": creator_id}],
        enable_cross_partition_query=True,
    ))


def delete_photo(photo_id: str) -> bool:
    try:
        _container("photos").delete_item(photo_id, partition_key=photo_id)
        return True
    except exceptions.CosmosResourceNotFoundError:
        return False


def update_photo_rating(photo_id: str, new_avg: float, new_count: int):
    photo = get_photo_by_id(photo_id)
    if photo:
        photo["average_rating"] = new_avg
        photo["rating_count"] = new_count
        _container("photos").replace_item(photo_id, photo)


def increment_comment_count(photo_id: str):
    photo = get_photo_by_id(photo_id)
    if photo:
        photo["comment_count"] = photo.get("comment_count", 0) + 1
        _container("photos").replace_item(photo_id, photo)


# ── Comments ──────────────────────────────────────────────────────────────────

def create_comment(photo_id: str, user_id: str, username: str,
                   text: str, sentiment: str, sentiment_score: float) -> dict:
    comment = {
        "id": str(uuid.uuid4()),
        "photo_id": photo_id,
        "user_id": user_id,
        "username": username,
        "text": text,
        "sentiment": sentiment,
        "sentiment_score": sentiment_score,
        "created_at": now_iso(),
    }
    _container("comments").create_item(comment)
    increment_comment_count(photo_id)
    return comment


def get_comments(photo_id: str) -> list:
    query = "SELECT * FROM c WHERE c.photo_id = @pid ORDER BY c.created_at DESC"
    return list(_container("comments").query_items(
        query=query,
        parameters=[{"name": "@pid", "value": photo_id}],
        enable_cross_partition_query=True,
    ))


# ── Ratings ───────────────────────────────────────────────────────────────────

def upsert_rating(photo_id: str, user_id: str, rating: int) -> dict:
    existing = _get_existing_rating(photo_id, user_id)
    if existing:
        existing["rating"] = rating
        existing["updated_at"] = now_iso()
        _container("ratings").replace_item(existing["id"], existing)
        record = existing
    else:
        record = {
            "id": str(uuid.uuid4()),
            "photo_id": photo_id,
            "user_id": user_id,
            "rating": rating,
            "created_at": now_iso(),
        }
        _container("ratings").create_item(record)

    # Recalculate average
    all_ratings = get_ratings_for_photo(photo_id)
    total = sum(r["rating"] for r in all_ratings)
    count = len(all_ratings)
    avg = round(total / count, 2) if count else 0.0
    update_photo_rating(photo_id, avg, count)
    return record


def _get_existing_rating(photo_id: str, user_id: str) -> dict | None:
    query = "SELECT * FROM c WHERE c.photo_id = @pid AND c.user_id = @uid"
    items = list(_container("ratings").query_items(
        query=query,
        parameters=[
            {"name": "@pid", "value": photo_id},
            {"name": "@uid", "value": user_id},
        ],
        enable_cross_partition_query=True,
    ))
    return items[0] if items else None


def get_ratings_for_photo(photo_id: str) -> list:
    query = "SELECT * FROM c WHERE c.photo_id = @pid"
    return list(_container("ratings").query_items(
        query=query,
        parameters=[{"name": "@pid", "value": photo_id}],
        enable_cross_partition_query=True,
    ))


def ensure_containers():
    """Called at startup to create containers if missing."""
    db = _get_db()
    for name, partition in [
        ("users", "/id"),
        ("photos", "/id"),
        ("comments", "/id"),
        ("ratings", "/id"),
    ]:
        try:
            db.create_container_if_not_exists(
                id=name, partition_key=PartitionKey(path=partition)
            )
        except Exception:
            pass
