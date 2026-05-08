import os
import jwt
import bcrypt
from datetime import datetime, timedelta, timezone

SECRET = os.environ.get("JWT_SECRET", "change-me")
ALGORITHM = "HS256"
TOKEN_EXPIRY_HOURS = 24


def hash_password(plain: str) -> str:
    return bcrypt.hashpw(plain.encode(), bcrypt.gensalt()).decode()


def verify_password(plain: str, hashed: str) -> bool:
    return bcrypt.checkpw(plain.encode(), hashed.encode())


def create_token(user_id: str, username: str, role: str) -> str:
    payload = {
        "sub": user_id,
        "username": username,
        "role": role,
        "exp": datetime.now(timezone.utc) + timedelta(hours=TOKEN_EXPIRY_HOURS),
        "iat": datetime.now(timezone.utc),
    }
    return jwt.encode(payload, SECRET, algorithm=ALGORITHM)


def decode_token(token: str) -> dict | None:
    try:
        return jwt.decode(token, SECRET, algorithms=[ALGORITHM])
    except jwt.ExpiredSignatureError:
        return None
    except jwt.InvalidTokenError:
        return None


def extract_token(req) -> dict | None:
    auth = req.headers.get("Authorization", "")
    if not auth.startswith("Bearer "):
        return None
    return decode_token(auth[7:])


def require_auth(req, role: str | None = None) -> tuple[dict | None, str | None]:
    claims = extract_token(req)
    if not claims:
        return None, "Unauthorized: missing or invalid token"
    if role and claims.get("role") != role:
        return None, f"Forbidden: requires role '{role}'"
    return claims, None
