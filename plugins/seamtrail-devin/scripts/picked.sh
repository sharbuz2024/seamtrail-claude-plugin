#!/bin/sh
# SeamTrail · the person picked this chat's project, in the Devin CLI (SEAM-254: the Claude Code plugin's picked.sh —
# SEAM-228 — in Devin's hook format): set_chat_project was called, so the turn-end check (stop.sh) names that project
# from now on — or, for "No project", stays quiet. Nothing leaves the computer.

. "$(dirname "$0")/lib.sh"
input=$(cat)
session=$(printf '%s' "$input" | grep -o '"session_id"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
[ -z "$session" ] && exit 0
# Refused (a project the person is not on, or both answers at once): nothing changed.
refused "$input" && exit 0

project=$(printf '%s' "$input" | grep -o '"projectId"[[:space:]]*:[[:space:]]*"[0-9a-fA-F-]\{36\}"' | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
if [ -n "$project" ]; then
  mkdir -p "$data" && printf '%s\n\n' "$project" > "$data/project-$session"
else
  rm -f "$data/project-$session"
fi
exit 0
