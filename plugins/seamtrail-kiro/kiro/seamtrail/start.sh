#!/bin/sh
# SeamTrail for Kiro · chat start (SEAM-264; the Claude Code plugin's start.sh: SEAM-215, SEAM-230, SEAM-228, SEAM-256).
# Kiro's SessionStart hook (the Kiro IDE 1.x and the Kiro CLI V3 read it from .kiro/hooks/seamtrail.json) registers this
# chat with SeamTrail — its id (Kiro's session id), its folder, and assistant=kiro so SeamTrail words its question for
# Kiro and names "a Kiro chat" on notes — and hands SeamTrail's plain-text answer to the agent: Kiro adds what a
# SessionStart command prints to the agent's context. The answer is the context of the project the person picked for
# this chat or, not picked yet, the question the agent asks at the first message ("Which SeamTrail project is this chat
# for?" — the git remote and branch only order its options). A Kiro hook cannot add the chat id to SeamTrail's tool
# calls (Claude Code's guard.sh does), so the agent is also told the chat id, to add itself (.kiro/steering/seamtrail.md
# says how). It keeps, on this computer, the chat's project, so the turn-end check (stop.sh) names it — or stays quiet.
# message.sh runs it at the first message when Kiro started a chat without it. Silent on any failure — a hook must never
# get in the way.

token="$SEAMTRAIL_TOKEN"
url="${SEAMTRAIL_URL:-https://mcp.seamtrail.com/mcp}"
input=$(cat)
data="${XDG_STATE_HOME:-$HOME/.local/state}/seamtrail/kiro"

session=$(printf '%s' "$input" | grep -o '"session_id"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
# A plain id only (letters, digits, - and _): it names files here, and SeamTrail takes no other.
case "$session" in *[!A-Za-z0-9_-]*) session="" ;; esac
[ -n "$session" ] || exit 0
mkdir -p "$data" 2>/dev/null || exit 0
# What chats untouched for a month left here goes.
find "$data" -type f -mtime +30 -exec rm -f {} + 2>/dev/null
# A new (or resumed) chat starts clean: nothing saved yet, not asked yet, no project known yet.
rm -f "$data/saved-$session" "$data/asked-$session" "$data/project-$session"
: > "$data/started-$session"

[ -n "$token" ] || exit 0
# Kiro runs a hook command in the workspace's root folder.
dir="$PWD"
remote=$(git -C "$dir" remote get-url origin 2>/dev/null)
branch=$(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null)

tmp=$(mktemp -d 2>/dev/null) || exit 0
# SEAM-273: this kit's version (Kiro has no plugin manifest), so SeamTrail can tell this chat when a newer one
# is out. Keep it equal to updates.json's kiro version (tests/updates.sh checks).
version="0.1.0"
if curl -s -f -G --max-time 10 "${url%/}/hook/start" \
  -H "Authorization: Bearer $token" \
  --data-urlencode "remote=$remote" \
  --data-urlencode "branch=$branch" \
  --data-urlencode "chat=$session" \
  --data-urlencode "folder=$dir" \
  --data-urlencode "assistant=kiro" \
  --data-urlencode "version=$version" \
  -D "$tmp/headers" -o "$tmp/body" 2>/dev/null; then
  cat "$tmp/body"
  # The chat id goes to the agent, who adds it to SeamTrail's calls (a Kiro hook cannot).
  printf "\n\nThis chat's SeamTrail chat id is %s: add chatId \"%s\" to every SeamTrail tool call (the SeamTrail steering file says why).\n" "$session" "$session"
  project=$(grep -i '^x-seamtrail-project:' "$tmp/headers" | head -1 | sed 's/^[^:]*:[[:space:]]*//' | tr -d '\r')
  name=$(grep -i '^x-seamtrail-project-name:' "$tmp/headers" | head -1 | sed 's/^[^:]*:[[:space:]]*//' | tr -d '\r')
  if [ -n "$project" ]; then
    printf '%s\n%s\n' "$project" "$name" > "$data/project-$session"
  fi
fi
rm -rf "$tmp"
exit 0
