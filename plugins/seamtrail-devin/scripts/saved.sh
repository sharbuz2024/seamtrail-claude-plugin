#!/bin/sh
# SeamTrail · a note was saved this turn, in the Devin CLI (SEAM-254: the Claude Code plugin's saved.sh — SEAM-215 —
# in Devin's hook format): remember, resolve, settle_question… was called, so the turn-end check (stop.sh) lets the
# agent finish without a reminder. Called with "change" (ask_seamtrail, undo_change), only when SeamTrail really
# changed something — ask_seamtrail's reply lists a step done, undo_change did not fail — because SeamTrail records
# that change itself, and a note about it would only repeat it; a question to SeamTrail saves nothing. Nothing leaves
# the computer.

. "$(dirname "$0")/lib.sh"
input=$(cat)
session=$(printf '%s' "$input" | grep -o '"session_id"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
[ -n "$session" ] || exit 0

if [ "$1" = "change" ]; then
  tool=$(printf '%s' "$input" | grep -o '"tool_name"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
  case "$tool" in
    *__undo_change)
      refused "$input" && exit 0
      ;;
    *)
      # The reply arrives as text inside the hook's JSON (Devin: tool_response.output), so its quotes are escaped,
      # once or more: \"did\":[ … \"done\":true
      printf '%s' "$input" | grep -Eq '\\*"did\\*"[[:space:]]*:[[:space:]]*\[' || exit 0
      printf '%s' "$input" | grep -Eq '\\*"done\\*"[[:space:]]*:[[:space:]]*true' || exit 0
      ;;
  esac
fi
mkdir -p "$data" && : > "$data/saved-$session"
exit 0
