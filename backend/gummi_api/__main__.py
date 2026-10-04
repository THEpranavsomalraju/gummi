"""Entry point for Databricks Apps: one uvicorn worker on DATABRICKS_APP_PORT (in-memory state needs one process)."""
import os

import uvicorn

if __name__ == "__main__":
    uvicorn.run("gummi_api.main:app", host="0.0.0.0", port=int(os.environ.get("DATABRICKS_APP_PORT", "8000")), workers=1,
                timeout_graceful_shutdown=5)
