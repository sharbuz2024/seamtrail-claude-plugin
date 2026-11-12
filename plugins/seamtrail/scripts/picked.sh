#!/bin/sh
# SeamTrail · the person picked this chat's project (SEAM-228): set_chat_project was called, so the turn-end check
# (stop.sh) names that project from now on — or, for "No project", stays quiet. Nothing leaves the computer.
# SEAM-325: for "No SeamTrail" (off: true) the chat is marked off here, and every hook stays quiet in it (off.sh).

input=$(cat)
data="$CLAUDE_PLUGIN_DATA"
session=$(printf '%s' "$input" | grep -o '"session_id"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
[ -z "$data" ] || [ -z "$session" ] && exit 0
# Refused (a project the person is not on, or both answers at once): nothing changed.
printf '%s' "$input" | grep -q '"isError"[[:space:]]*:[[:space:]]*true' && exit 0

# SEAM-325: "No SeamTrail". What this computer kept for the chat goes too: its message id, tickets and reminder.
if printf '%s' "$input" | grep -q '"off"[[:space:]]*:[[:space:]]*true'; then
  mkdir -p "$data" && : > "$data/off-$session"
  rm -f "$data/project-$session" "$data/turn-$session.json" "$data/tickets-$session.jsonl" "$data/remind-$session"
  exit 0
fi
# A project or "No project" turns SeamTrail back on in the chat.
rm -f "$data/off-$session"

project=$(printf '%s' "$input" | grep -o '"projectId"[[:space:]]*:[[:space:]]*"[0-9a-fA-F-]\{36\}"' | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
if [ -n "$project" ]; then
  mkdir -p "$data" && printf '%s\n\n' "$project" > "$data/project-$session"
else
  rm -f "$data/project-$session"
fi
exit 0
