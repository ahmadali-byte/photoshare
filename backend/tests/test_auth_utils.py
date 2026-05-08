"""Unit tests for auth utilities — no Azure dependencies required."""
import pytest
import sys
import os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

os.environ.setdefault("JWT_SECRET", "test-secret")
os.environ.setdefault("COSMOS_ENDPOINT", "https://mock.documents.azure.com:443/")
os.environ.setdefault("COSMOS_KEY", "mock")
os.environ.setdefault("COSMOS_DATABASE", "photoshare")
os.environ.setdefault("BLOB_CONNECTION_STRING", "DefaultEndpointsProtocol=https;AccountName=mock;AccountKey=bW9jaw==;EndpointSuffix=core.windows.net")
os.environ.setdefault("VISION_ENDPOINT", "https://mock.cognitiveservices.azure.com/")
os.environ.setdefault("VISION_KEY", "mock")
os.environ.setdefault("LANGUAGE_ENDPOINT", "https://mock.cognitiveservices.azure.com/")
os.environ.setdefault("LANGUAGE_KEY", "mock")

from utils.auth_utils import hash_password, verify_password, create_token, decode_token


class TestPasswordHashing:
    def test_hash_produces_different_string(self):
        pw = "MySecretPassword123"
        hashed = hash_password(pw)
        assert hashed != pw

    def test_verify_correct_password(self):
        pw = "TestPassword!"
        assert verify_password(pw, hash_password(pw))

    def test_reject_wrong_password(self):
        hashed = hash_password("correct-horse")
        assert not verify_password("wrong-pony", hashed)

    def test_bcrypt_salts_differ(self):
        pw = "same-password"
        assert hash_password(pw) != hash_password(pw)


class TestJWTTokens:
    def test_create_and_decode_token(self):
        token = create_token("user-123", "alice", "consumer")
        payload = decode_token(token)
        assert payload is not None
        assert payload["sub"] == "user-123"
        assert payload["username"] == "alice"
        assert payload["role"] == "consumer"

    def test_invalid_token_returns_none(self):
        assert decode_token("not.a.valid.token") is None

    def test_tampered_token_returns_none(self):
        token = create_token("user-456", "bob", "creator")
        tampered = token[:-4] + "XXXX"
        assert decode_token(tampered) is None

    def test_creator_role_preserved(self):
        token = create_token("creator-1", "carol", "creator")
        payload = decode_token(token)
        assert payload["role"] == "creator"
