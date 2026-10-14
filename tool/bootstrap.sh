#!/usr/bin/env bash
# One command to get a runnable project from a fresh clone:
#   bash tool/bootstrap.sh && flutter run
# `flutter create` only fills in files that are missing, so the committed Android overrides
# (manifest, MainActivity, icons, themes) are kept.
set -euo pipefail
cd "$(dirname "$0")/.."

flutter create --org com.koushi --project-name almanac --platforms=android,ios --no-pub .
python3 tool/patch_android.py

if ! python3 -c "import PIL" 2>/dev/null; then
  python3 -m pip install --quiet pillow 2>/dev/null \
    || python3 -m pip install --quiet --user pillow 2>/dev/null \
    || python3 -m pip install --quiet --user --break-system-packages pillow
fi
python3 tool/make_icons.py

flutter pub get
echo "Ready. Run: flutter run"
