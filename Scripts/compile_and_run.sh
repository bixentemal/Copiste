#!/usr/bin/env bash
# Kill, build, test, package, relaunch, verify. The loop to run after any code change.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
APP="${ROOT}/Copiste.app"

log()  { printf '==> %s\n' "$*"; }
fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

log "Stopping running instances"
"${ROOT}/Scripts/kill_copiste.sh"

log "swift build";              swift build -q            || fail "build failed"
log "swift test";               swift test -q             || fail "tests failed"
log "package app";              "${ROOT}/Scripts/package_app.sh" debug
log "launch";                   open "${APP}"

sleep 1
if pgrep -f "Copiste.app/Contents/MacOS/Copiste" >/dev/null 2>&1; then
  log "OK: Copiste is running."
else
  fail "App exited immediately. Check Console.app (User Reports) for a crash log."
fi
