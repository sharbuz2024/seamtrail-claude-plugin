#!/bin/sh
# SeamTrail · the person picked this chat's project (SEAM-253: the Claude Code plugin's picked.sh, for Gemini CLI's
# AfterTool): set_chat_project was called, so the turn-end check (stop.sh) names that project from now on — or, for
# "No project", stays quiet. Nothing leaves the computer.

. "$(dirname "$0")/common.sh"
[ -n "$session" ] || exit 0
seamtrail_tool || exit 0
# Refused (a project the person is not on, or both answers at once): nothing changed.
failed && exit 0

# The call's own projectId (its arguments come before its result, whose quotes arrive escaped).
project=$(printf '%s' "$input" | grep -o '"projectId"[[:space:]]*:[[:space:]]*"[0-9a-fA-F-]\{36\}"' | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
if [ -n "$project" ]; then
  mkdir -p "$data" && printf '%s\n\n' "$project" > "$data/project-$session"
else
  rm -f "$data/project-$session"
fi
exit 0
