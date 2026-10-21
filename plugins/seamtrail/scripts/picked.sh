#!/bin/sh
# SeamTrail · the person picked this chat's project (SEAM-228): set_chat_project was called, so the turn-end check
# (stop.sh) names that project from now on — or, for "No project", stays quiet. Nothing leaves the computer.

input=$(cat)
data="$CLAUDE_PLUGIN_DATA"
session=$(printf '%s' "$input" | grep -o '"session_id"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
[ -z "$data" ] || [ -z "$session" ] && exit 0
# Refused (a project the person is not on, or both answers at once): nothing changed.
printf '%s' "$input" | grep -q '"isError"[[:space:]]*:[[:space:]]*true' && exit 0

project=$(printf '%s' "$input" | grep -o '"projectId"[[:space:]]*:[[:space:]]*"[0-9a-fA-F-]\{36\}"' | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
if [ -n "$project" ]; then
  mkdir -p "$data" && printf '%s\n\n' "$project" > "$data/project-$session"
else
  rm -f "$data/project-$session"
fi
exit 0
