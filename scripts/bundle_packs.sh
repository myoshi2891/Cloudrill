#!/bin/bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
exec "$repo_root/content/.venv/bin/python" "$repo_root/scripts/bundle_packs.py" "$@"
