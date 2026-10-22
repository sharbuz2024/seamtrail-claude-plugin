#!/bin/sh
# SeamTrail · a note was saved this turn (SEAM-255; the Claude Code plugin's saved.sh — SEAM-215 — for VS Code):
# remember, resolve, settle_question or widen_memory was called, so the turn-end check (stop.sh) lets the agent finish
# without a reminder. Called with "change" (ask_seamtrail, undo_change), only when SeamTrail really changed something —
# ask_seamtrail's reply lists a step done, undo_change did not fail — because SeamTrail records that change itself, and
# a note about it would only repeat it; a question to SeamTrail saves nothing. VS Code drops a hook's matcher, so this
# runs after every tool and checks the tool's name itself; a call that failed counts for nothing. Nothing leaves the
# computer.

input=$(cat)
# Most calls are to other tools: done at once (no process started) unless the input names SeamTrail anywhere.
case "$input" in *[Ss][Ee][Aa][Mm][Tt][Rr][Aa][Ii][Ll]*) ;; *) exit 0 ;; esac
. "$(dirname "$0")/lib.sh"
[ -n "$session" ] || exit 0

if [ "$1" = "change" ]; then
  is_tool ask_seamtrail undo_change || exit 0
  failed && exit 0
  case "$tool" in
    *undo_change) ;;
    *)
      # The reply arrives as text inside the hook's JSON, so its quotes may be escaped: \"did\":[ … \"done\":true
      printf '%s' "$input" | grep -Eq '\\?"did\\?"[[:space:]]*:[[:space:]]*\[' || exit 0
      printf '%s' "$input" | grep -Eq '\\?"done\\?"[[:space:]]*:[[:space:]]*true' || exit 0
      ;;
  esac
else
  is_tool remember resolve settle_question widen_memory || exit 0
  failed && exit 0
fi
mkdir -p "$data" && : > "$data/saved-$session"
exit 0
