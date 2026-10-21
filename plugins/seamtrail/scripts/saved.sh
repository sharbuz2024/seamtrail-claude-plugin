#!/bin/sh
# SeamTrail · a note was saved this turn (SEAM-215): remember, resolve, settle_question… was called, so the
# turn-end check (stop.sh) lets the agent finish without a reminder. Nothing leaves the computer.

session=$(grep -o '"session_id"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
if [ -n "$CLAUDE_PLUGIN_DATA" ] && [ -n "$session" ]; then
  mkdir -p "$CLAUDE_PLUGIN_DATA" && : > "$CLAUDE_PLUGIN_DATA/saved-$session"
fi
exit 0
