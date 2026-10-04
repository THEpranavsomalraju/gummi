#!/usr/bin/env bash
# Deploy the Gummi App: vendor Data's model packages, sync the source, deploy, wait for /health.
#   scripts/deploy.sh
# Redeploy before filming and judging (Free Edition Apps can stop after a runtime window). A full redeploy takes about
# 2 minutes; the App then loads the model and replay tables in the background (about 20 s, /health says warming_up).
set -euo pipefail
cd "$(dirname "$0")/.."
PROFILE="${DATABRICKS_CONFIG_PROFILE:-gummi}"
DEST="/Workspace/Users/somalrajupc@gmail.com/gummi-backend"

# gummi_model and gummi_activity ship in the App bundle (D-34); runtime needs numpy and pandas only
rm -rf vendor && mkdir -p vendor
for pkg in gummi_model gummi_activity; do
  rsync -a --exclude '__pycache__' "../data/$pkg" vendor/
done

databricks sync . "$DEST" --profile "$PROFILE" --full \
  --include 'vendor/**' --exclude '.cache/**' --exclude 'tests/**' --exclude 'secrets/**' --exclude '.venv/**'
databricks apps deploy gummi --source-code-path "$DEST" --profile "$PROFILE" -o json | grep -E '"state"|"message"' | head -2
