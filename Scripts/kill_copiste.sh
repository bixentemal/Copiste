#!/usr/bin/env bash
# Stop every running Copiste, packaged or from .build.
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
for _ in {1..10}; do
  pkill -f "Copiste.app/Contents/MacOS/Copiste" 2>/dev/null || true
  pkill -f "${ROOT}/.build/debug/Copiste" 2>/dev/null || true
  pkill -f "${ROOT}/.build/release/Copiste" 2>/dev/null || true
  pgrep -f "Copiste.app/Contents/MacOS/Copiste" >/dev/null 2>&1 || exit 0
  sleep 0.3
done
