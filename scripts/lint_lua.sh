#!/usr/bin/env bash
# Run selene over the mod, resolving the binary even when ~/.cargo/bin is off PATH.
# No args: two passes -- strict selene.toml over runtime code, lenient selene-tests.toml over tests/
# (so expected test-harness noise never buries real runtime findings). With args: pass straight through.
# Usage: bash scripts/lint_lua.sh [selene args...]
set -u
cd "$(dirname "$0")/../neuro-game" || exit 2

SELENE="$(command -v selene || true)"
if [ -z "$SELENE" ] && [ -x "$HOME/.cargo/bin/selene" ]; then
  SELENE="$HOME/.cargo/bin/selene"
fi
if [ -z "$SELENE" ]; then
  echo "selene not found on PATH or in \$HOME/.cargo/bin -- install with: cargo install selene" >&2
  exit 127
fi

if [ "$#" -gt 0 ]; then
  exec "$SELENE" "$@"
fi

RUNTIME_DIRS=(core context force facts handlers hud render util ../scripts ../tools neuro-game.lua)
rc=0
echo "== runtime (strict: selene.toml) =="
"$SELENE" --config selene.toml "${RUNTIME_DIRS[@]}" || rc=$?
echo "== tests (lenient: selene-tests.toml) =="
"$SELENE" --config selene-tests.toml tests || rc=$?

LUACHECK="$(command -v luacheck || true)"
if [ -n "$LUACHECK" ]; then
  echo "== dead code (luacheck: unreachable, dead stores, unused) =="
  "$LUACHECK" "${RUNTIME_DIRS[@]}" --no-color --codes --quiet || rc=$?
else
  echo "== dead code: luacheck not installed -- install with: pacman -S luacheck =="
fi

exit $rc
