import json
import os
import sys
import traceback

import azure.functions as func

app = func.FunctionApp(http_auth_level=func.AuthLevel.ANONYMOUS)

# ── Capture any import errors at module load time ─────────────────────────────
_import_errors = {}
_sys_path = list(sys.path)

try:
    from utils import auth_utils
except Exception as e:
    _import_errors["auth_utils"] = traceback.format_exc()

try:
    from utils import cosmos_db
except Exception as e:
    _import_errors["cosmos_db"] = traceback.format_exc()

try:
    from utils import blob_storage
except Exception as e:
    _import_errors["blob_storage"] = traceback.format_exc()

try:
    from utils import cognitive
except Exception as e:
    _import_errors["cognitive"] = traceback.format_exc()

_all_ok = not _import_errors

# ── Diagnostic endpoint ───────────────────────────────────────────────────────

@app.route(route="diag", methods=["GET"])
def diag(req: func.HttpRequest) -> func.HttpResponse:
    return func.HttpResponse(
        json.dumps({
            "imports_ok": _all_ok,
            "import_errors": _import_errors,
            "sys_path": _sys_path,
            "python_version": sys.version,
            "env_vars": {k: ("SET" if v else "EMPTY") for k, v in os.environ.items()
                        if k in ["COSMOS_ENDPOINT", "COSMOS_KEY", "BLOB_CONNECTION_STRING",
                                 "VISION_ENDPOINT", "VISION_KEY", "LANGUAGE_ENDPOINT",
                                 "LANGUAGE_KEY", "JWT_SECRET", "ADMIN_SECRET"]},
        }, indent=2),
        status_code=200,
        headers={"Content-Type": "application/json"},
    )


@app.route(route="health", methods=["GET"])
def health(req: func.HttpRequest) -> func.HttpResponse:
    return func.HttpResponse(
        json.dumps({"status": "healthy", "imports_ok": _all_ok}),
        status_code=200,
        headers={"Content-Type": "application/json"},
    )
