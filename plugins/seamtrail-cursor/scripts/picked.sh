#!/bin/sh
# SeamTrail · the person picked this chat's project (SEAM-228) — for Cursor (SEAM-256), on postToolUse and
# afterMCPExecution (either one is enough). set_chat_project was called, so the turn-end check (stop.sh) names that
# project from now on — or, for "No project", stays quiet. Nothing leaves the computer.

lib="$(dirname "$0")/lib.sh"
[ -f "$lib" ] || exit 0
. "$lib"

input=$(cat)
chat=$(st_chat "$input")
[ -n "$chat" ] || exit 0
[ "$(st_tool "$input")" = set_chat_project ] || exit 0
# Refused (a project the person is not on, or both answers at once): nothing changed.
st_failed "$input" && exit 0

# The call's projectId; afterMCPExecution sends the arguments as a JSON string, so its quotes may be escaped.
project=$(printf '%s' "$input" | grep -o '\\*"projectId\\*"[[:space:]]*:[[:space:]]*\\*"[0-9a-fA-F-]\{36\}' | head -n 1 \
  | grep -o '[0-9a-fA-F-]\{36\}$')
if [ -n "$project" ]; then
  mkdir -p "$st_state" 2>/dev/null && printf '%s\n\n' "$project" > "$st_state/project-$chat"
else
  rm -f "$st_state/project-$chat"
fi
exit 0
