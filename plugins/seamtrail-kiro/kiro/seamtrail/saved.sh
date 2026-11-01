#!/bin/sh
# SeamTrail for Kiro · a note was saved this turn (SEAM-264; the Claude Code plugin's saved.sh, SEAM-215). Kiro's
# PostToolUse hook after remember, resolve, settle_question or widen_memory — a SeamTrail server's tool, known by its
# name in Kiro's tool id (mcp_seamtrail_remember; @SeamTrail/remember in older Kiro CLIs) — marks the turn saved, so the next message brings no save reminder (stop.sh, remind.sh). Called with "change" (ask_seamtrail, undo_change),
# only when SeamTrail really changed something — ask_seamtrail's reply lists a step done, undo_change did not fail —
# because SeamTrail records that change itself, and a note about it would only repeat it; a question to SeamTrail saves
# nothing. Nothing leaves the computer.

input=$(cat)
data="${XDG_STATE_HOME:-$HOME/.local/state}/seamtrail/kiro"
session=$(printf '%s' "$input" | grep -o '"session_id"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
case "$session" in *[!A-Za-z0-9_-]*) session="" ;; esac
[ -n "$session" ] || exit 0
tool=$(printf '%s' "$input" | grep -o '"tool_name"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"\([^"]*\)"$/\1/' | tr 'A-Z' 'a-z')
# Only SeamTrail's own tools count, whatever the hook's matcher let through.
case "$tool" in *seamtrail*) ;; *) exit 0 ;; esac

if [ "$1" = "change" ]; then
  case "$tool" in
    *undo_change)
      # Refused: nothing was undone (MCP's isError; the Kiro CLI's "success": false).
      printf '%s' "$input" | grep -q '"isError"[[:space:]]*:[[:space:]]*true' && exit 0
      printf '%s' "$input" | grep -q '"success"[[:space:]]*:[[:space:]]*false' && exit 0
      ;;
    *ask_seamtrail)
      # The reply arrives as text inside the hook's JSON, so its quotes may be escaped: \"did\":[ … \"done\":true
      printf '%s' "$input" | grep -Eq '\\?"did\\?"[[:space:]]*:[[:space:]]*\[' || exit 0
      printf '%s' "$input" | grep -Eq '\\?"done\\?"[[:space:]]*:[[:space:]]*true' || exit 0
      ;;
    *) exit 0 ;;
  esac
else
  case "$tool" in *remember | *resolve | *settle_question | *widen_memory) ;; *) exit 0 ;; esac
fi
mkdir -p "$data" && : > "$data/saved-$session"
exit 0
