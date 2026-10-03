"""Settings from environment variables (app.yaml in Databricks, shell locally)."""
import os

VERSION = "0.1.0"
MODE = os.environ.get("GUMMI_MODE", "mock")
CATALOG = os.environ.get("GUMMI_CATALOG", "workspace")
TIMEZONE = os.environ.get("GUMMI_TIMEZONE", "America/New_York")
HIGH_LINE = 140.0
LOW_LINE = 70.0
DELAY_MINUTES = 60
MODEL_VERSION = "gummi_model_v1"

# Real replay events land in events/ (the gummi_stream pipeline reads it). Mock events go to a sibling folder so
# synthetic data never reaches the stream tables (D-50).
LANDING_ROOT = f"/Volumes/{CATALOG}/gummi_data/landing"
LANDING_DIR = os.environ.get("GUMMI_LANDING_DIR", f"{LANDING_ROOT}/mock_events" if MODE == "mock" else f"{LANDING_ROOT}/events")
LANDING_ENABLED = os.environ.get("GUMMI_LANDING_ENABLED", "true").lower() == "true"
LANDING_INTERVAL_S = 5.0

PING_SECONDS = 15.0
MOCK_CARD_SECONDS = float(os.environ.get("GUMMI_MOCK_CARD_SECONDS", "60"))
MOCK_STATE_SECONDS = 5.0

# Participants replayed: 001 to 016 without 015 (D-20 exclusion, D-37 not replayed)
PARTICIPANTS = [f"p_{i:03d}" for i in range(1, 17) if i != 15]
