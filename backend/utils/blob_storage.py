import os
import uuid
from azure.storage.blob import BlobServiceClient, ContentSettings

_service: BlobServiceClient | None = None
CONTAINER = os.environ.get("BLOB_CONTAINER", "photos")


def _get_service() -> BlobServiceClient:
    global _service
    if _service is None:
        _service = BlobServiceClient.from_connection_string(
            os.environ["BLOB_CONNECTION_STRING"]
        )
    return _service


def upload_photo(file_bytes: bytes, content_type: str, original_filename: str) -> str:
    ext = original_filename.rsplit(".", 1)[-1].lower() if "." in original_filename else "jpg"
    blob_name = f"{uuid.uuid4()}.{ext}"

    service = _get_service()
    container = service.get_container_client(CONTAINER)

    # Create container if missing (idempotent)
    try:
        container.create_container(public_access="blob")
    except Exception:
        pass

    blob = container.get_blob_client(blob_name)
    blob.upload_blob(
        file_bytes,
        overwrite=True,
        content_settings=ContentSettings(content_type=content_type),
    )
    return blob.url


def delete_photo(blob_url: str) -> bool:
    try:
        service = _get_service()
        blob_name = blob_url.split(f"/{CONTAINER}/")[-1]
        service.get_blob_client(container=CONTAINER, blob=blob_name).delete_blob()
        return True
    except Exception:
        return False
