#!/bin/sh
# SeamTrail · chat start (SEAM-215, SEAM-230, SEAM-228). Registers this chat with SeamTrail (its id, name and folder), so
# the chat id the guard adds to SeamTrail calls is believed. SeamTrail answers with plain text, which Claude Code adds to
# the chat: the context of the project the person picked for this chat, or, not picked yet, the question Claude asks at
# the first message ("Which SeamTrail project is this chat for?" — the git remote and branch only order its options).
# It also keeps, on this computer, the chat's project, so the turn-end check (stop.sh) names it — or stays quiet.
# Silent on any failure — a hook must never get in the way.

token="${CLAUDE_PLUGIN_OPTION_SEAMTRAIL_TOKEN:-$SEAMTRAIL_TOKEN}"
url="${CLAUDE_PLUGIN_OPTION_SEAMTRAIL_URL:-${SEAMTRAIL_URL:-https://mcp.seamtrail.com/mcp}}"
input=$(cat)
data="$CLAUDE_PLUGIN_DATA"

session=$(printf '%s' "$input" | grep -o '"session_id"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
# SEAM-230: the chat's custom name, when it has one, so SeamTrail can show the person which chat a note came from.
title=$(printf '%s' "$input" | grep -o '"session_title"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
# A new (or resumed) chat starts clean: nothing saved yet, no project known yet.
if [ -n "$data" ] && [ -n "$session" ]; then rm -f "$data/saved-$session" "$data/project-$session"; fi

[ -z "$token" ] && exit 0
dir="${CLAUDE_PROJECT_DIR:-$PWD}"
remote=$(git -C "$dir" remote get-url origin 2>/dev/null)
branch=$(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null)

tmp=$(mktemp -d 2>/dev/null) || exit 0
if curl -s -f -G --max-time 10 "${url%/}/hook/start" \
  -H "Authorization: Bearer $token" \
  --data-urlencode "remote=$remote" \
  --data-urlencode "branch=$branch" \
  --data-urlencode "chat=$session" \
  --data-urlencode "chatName=$title" \
  --data-urlencode "folder=$dir" \
  -D "$tmp/headers" -o "$tmp/body" 2>/dev/null; then
  cat "$tmp/body"
  project=$(grep -i '^x-seamtrail-project:' "$tmp/headers" | head -1 | sed 's/^[^:]*:[[:space:]]*//' | tr -d '\r')
  name=$(grep -i '^x-seamtrail-project-name:' "$tmp/headers" | head -1 | sed 's/^[^:]*:[[:space:]]*//' | tr -d '\r')
  if [ -n "$data" ] && [ -n "$session" ] && [ -n "$project" ]; then
    mkdir -p "$data" && printf '%s\n%s\n' "$project" "$name" > "$data/project-$session"
  fi
fi
rm -rf "$tmp"
exit 0
