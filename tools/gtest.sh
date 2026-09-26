#!/usr/bin/env bash
# Run Godot against a PRIVATE COPY of this repo, so parallel agents never share a .godot/ cache,
# never see each other's half-written files, and never share user:// (saves).
#
# Usage:
#   tools/gtest.sh <env-name> [godot args...]
#   tools/gtest.sh --snapshot            # orchestrator only: freeze the current repo as the baseline
#
# <env-name> is your module id (see tools/owners/*.txt), optionally with a suffix for a second
# concurrent run: "items", "items-demo", "world-bg"...
#
# How the private copy is built (default = ISOLATED mode):
#   1. the frozen baseline (snapshot taken by the orchestrator at the start of the wave), then
#   2. YOUR module's files from the live repo (globs in tools/owners/<module>.txt), then
#   3. any extra live paths in GTEST_EXTRA (e.g. GTEST_EXTRA="assets/models assets/icons").
# So other agents' in-progress edits never break your runs. GTEST_FULL=1 copies the whole live
# repo instead (integration runs).
#
# Examples:
#   tools/gtest.sh items res://tests/test_runner.tscn -- --filter=test_items         # unit tests
#   tools/gtest.sh items res://tools/godot/parse_check.tscn -- --path=res://scripts/items  # parse check
#   GTEST_WINDOWED=1 tools/gtest.sh world-demo res://tests/scenes/world_demo.tscn    # real window
#   GTEST_EXTRA="assets/models" tools/gtest.sh world res://tests/scenes/world_demo.tscn
#
# Env vars:
#   GTEST_TIMEOUT=180   seconds before the Godot run is killed (import pass has its own 400 s)
#   GTEST_WINDOWED=1    real window instead of --headless (keep such runs short & self-quitting)
#   GTEST_NO_IMPORT=1   skip the --import pass (only if nothing changed since the last run)
#   GTEST_CLEAN=1       wipe the env's .godot/ cache first (after a crash / weird import state)
#   GTEST_FULL=1        copy the whole live repo (integration)
#   GTEST_EXTRA="a b"   extra live repo paths to overlay in isolated mode
#
# Output: Godot's output, then an error summary splitting SCRIPT ERROR / Parse Error lines into
# errors in YOUR files and in OTHER modules' files. Exit code: Godot's exit code if non-zero,
# else 3 if there are errors in your files, else 0.
# The repo path is exported as GTEST_REPO so demos can write screenshots into the real repo:
#   OS.get_environment("GTEST_REPO") + "/docs/screenshots/<module>/..."
set -uo pipefail
GODOT="${GODOT:-/opt/godot/Godot_v4.6.1-stable_linux.x86_64}"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="${GTEST_ROOT:-/tmp/claude-1000/-home-filip-repos-mashuprpg/f8472f46-7f0b-4364-b048-d69d880841c2/scratchpad/gtest}"
BASE="$ROOT/_baseline"
RSYNC_EXCLUDES=(--exclude '.godot/' --exclude '*.import' --exclude '.tmp/' --exclude '*.tmp' --exclude 'docs/screenshots/' --exclude '.gtest_*')
mkdir -p "$ROOT"

if [ "${1:-}" = "--snapshot" ]; then
  mkdir -p "$BASE"
  rsync -a --delete "${RSYNC_EXCLUDES[@]}" "$REPO/" "$BASE/"
  echo "[gtest] baseline snapshot updated: $BASE"
  exit 0
fi

NAME="${1:?usage: gtest.sh <env-name> [godot args...]}"; shift
DEST="$ROOT/$NAME"
mkdir -p "$DEST"

# One run per env at a time.
exec 9>"$DEST.lock"
if ! flock -w 1200 9; then echo "[gtest] env '$NAME' is busy (another run holds the lock)"; exit 97; fi
[ -n "${GTEST_CLEAN:-}" ] && rm -rf "$DEST/.godot"

# Find the owners file: the longest module id that equals NAME or prefixes it followed by - or _.
OWNERS="-"
best=0
for f in "$REPO"/tools/owners/*.txt; do
  m="$(basename "$f" .txt)"
  if [ "$NAME" = "$m" ] || [[ "$NAME" == "$m-"* ]] || [[ "$NAME" == "$m"_* ]]; then
    if [ ${#m} -gt $best ]; then best=${#m}; OWNERS="$f"; fi
  fi
done

if [ -n "${GTEST_FULL:-}" ] || [ ! -d "$BASE" ] || [ "$OWNERS" = "-" ]; then
  rsync -a --delete "${RSYNC_EXCLUDES[@]}" "$REPO/" "$DEST/"
  MODE="full"
else
  rsync -a --delete "${RSYNC_EXCLUDES[@]}" "$BASE/" "$DEST/"
  LIST="$DEST.files"
  (cd "$REPO" && shopt -s globstar nullglob dotglob && while IFS= read -r g; do
      [ -z "$g" ] && continue; [[ "$g" == \#* ]] && continue
      for p in $g; do echo "$p"; done
    done < "$OWNERS"
    for p in ${GTEST_EXTRA:-}; do [ -e "$p" ] && echo "$p"; done) | grep -v '/\.tmp/' | grep -v '\.tmp$' | sort -u > "$LIST"
  rsync -a -r --files-from="$LIST" "${RSYNC_EXCLUDES[@]}" "$REPO/" "$DEST/"
  MODE="isolated ($(basename "$OWNERS" .txt) overlay on baseline)"
fi

# Private user:// per env (saves, logs).
printf '[application]\nconfig/use_custom_user_dir=true\nconfig/custom_user_dir_name="mashuprpg_gtest_%s"\n' "$NAME" > "$DEST/override.cfg"
export GTEST_REPO="$REPO"
echo "[gtest] env=$NAME mode=$MODE"

if [ -z "${GTEST_NO_IMPORT:-}" ]; then
  timeout 400 "$GODOT" --headless --path "$DEST" --import >"$DEST/.gtest_import.log" 2>&1
  rc=$?
  if [ $rc -ne 0 ]; then echo "[gtest] import pass exited with $rc (see $DEST/.gtest_import.log)"; fi
  grep -E "SCRIPT ERROR|Parse Error|Error importing|ERROR: .*res://" "$DEST/.gtest_import.log" | grep -vE "leaked at exit|Pages in use" | head -30
fi

HEADLESS="--headless"
if [ -n "${GTEST_WINDOWED:-}" ]; then HEADLESS=""; fi
LOG="$DEST/.gtest_run.log"
timeout "${GTEST_TIMEOUT:-180}" "$GODOT" $HEADLESS --path "$DEST" "$@" 2>&1 | tee "$LOG"
rc=${PIPESTATUS[0]}
if [ "$rc" = "124" ]; then echo "[gtest] TIMEOUT after ${GTEST_TIMEOUT:-180}s"; fi
python3 "$REPO/tools/gtest_classify.py" "$LOG" "$OWNERS" "$REPO"
crc=$?
if [ "$rc" != "0" ]; then exit "$rc"; fi
exit "$crc"
