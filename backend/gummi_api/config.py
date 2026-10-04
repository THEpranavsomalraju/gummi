"""Settings from environment variables (app.yaml in Databricks, shell locally)."""
import os
import sys
from pathlib import Path

VERSION = "0.2.0"
MODE = os.environ.get("GUMMI_MODE", "live")          # "live": real model and replay. "mock": synthetic (tests only)
CATALOG = os.environ.get("GUMMI_CATALOG", "workspace")
TIMEZONE = os.environ.get("GUMMI_TIMEZONE", "America/New_York")
HIGH_LINE = 140.0
LOW_LINE = 70.0
DELAY_MINUTES = 60
MODEL_VERSION = "gummi_model_v1"
WAREHOUSE_ID = os.environ.get("GUMMI_WAREHOUSE_ID", "1b929fe5bf415d65")
LLM_ENDPOINT = os.environ.get("GUMMI_LLM_ENDPOINT", "databricks-gpt-oss-120b")
LLM_FALLBACK = os.environ.get("GUMMI_LLM_FALLBACK", "databricks-qwen3-next-80b-a3b-instruct")
AGENT_ENDPOINT = os.environ.get("GUMMI_AGENT_ENDPOINT", "databricks-qwen3-next-80b-a3b-instruct")   # background agents (D-56)
JUDGE_ENDPOINT = os.environ.get("GUMMI_JUDGE_ENDPOINT", "databricks-llama-4-maverick")     # Reviewer agent (D-57)
INSIGHTS_ENDPOINT = os.environ.get("GUMMI_INSIGHTS_ENDPOINT", "mas-becc8b0e-endpoint")
MLFLOW_EXPERIMENT_ID = os.environ.get("GUMMI_MLFLOW_EXPERIMENT_ID", "3505481683626519")

BACKEND = Path(__file__).resolve().parents[1]
# gummi_model and gummi_activity: read from ../data when developing (always the current code), from backend/vendor
# in the App bundle, where scripts/deploy.sh copies them
for p in (BACKEND.parent / "data", BACKEND / "vendor"):
    if (p / "gummi_model").is_dir() and str(p) not in sys.path:
        sys.path.insert(0, str(p))
        break

MODEL_VOLUME_DIR = os.environ.get("GUMMI_MODEL_DIR", f"/Volumes/{CATALOG}/gummi_ml/artifacts/gummi_model_v1")
CACHE_DIR = Path(os.environ.get("GUMMI_CACHE_DIR", BACKEND / ".cache"))
REPLAY_SOURCE = os.environ.get("GUMMI_REPLAY_SOURCE", "sql")    # "sql" (Delta via the warehouse) or a folder of CSVs

# Real replay events land in the folder the gummi_stream pipeline reads (app.yaml sets events_live/ since the reset). Mock events go to a sibling folder so
# synthetic data never reaches the stream tables (D-50).
LANDING_ROOT = f"/Volumes/{CATALOG}/gummi_data/landing"
LANDING_DIR = os.environ.get("GUMMI_LANDING_DIR", f"{LANDING_ROOT}/mock_events" if MODE == "mock" else f"{LANDING_ROOT}/events")
LANDING_ENABLED = os.environ.get("GUMMI_LANDING_ENABLED", "true").lower() == "true"
LANDING_INTERVAL_S = 5.0

# Session, lessons and Dexcom tokens persist to the volume; tests turn this off so they never touch real state
PERSIST = os.environ.get("GUMMI_PERSIST", "true").lower() == "true"

PING_SECONDS = 15.0
STATE_PUSH_SECONDS = 1.0            # state events at most once per second (CONTRACT section 5)
MOCK_CARD_SECONDS = float(os.environ.get("GUMMI_MOCK_CARD_SECONDS", "60"))
MOCK_STATE_SECONDS = 5.0
GOLD_REFRESH_SECONDS = 20.0

# Replay engine
DEFAULT_START = "day6T05:00"        # D-62: the 05:54 standardized breakfast comes due on screen
DUE_AUTOLOG_MIN = 10                # D-27: unlogged due meals auto-log after 10 replay minutes
UPCOMING_DUE_MIN = 360              # D-36: next 6 replay hours
NOWCAST_EVERY_MIN = 60              # one nowcast prediction per participant per replay hour
WALK_COOLDOWN_MIN = 45              # CONTRACT section 7
PROUD_SECONDS = 20                  # CONTRACT section 9

# Participants replayed: 001 to 016 without 015 (D-20 exclusion, D-37 not replayed)
PARTICIPANTS = [f"p_{i:03d}" for i in range(1, 17) if i != 15]
