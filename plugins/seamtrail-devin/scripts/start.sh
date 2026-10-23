#!/bin/sh
# SeamTrail · chat start, in the Devin CLI (SEAM-254: the Claude Code plugin's start.sh — SEAM-215, SEAM-230, SEAM-228 —
# in Devin's hook format). Registers this chat with SeamTrail (its id and folder), so the chat id the guard adds to
# SeamTrail calls is believed. SeamTrail answers with plain text, which this hook hands to Devin as context (Devin takes
# it only as JSON: hookSpecificOutput.additionalContext): the context of the project the person picked for this chat,
# or, not picked yet, the question Devin asks at the first message ("Which SeamTrail project is this chat for?" —
# assistant=devin has SeamTrail word it for Devin and label the chat's notes "a Devin chat"; the git remote and branch
# only order its options). It also keeps, on this computer, the chat's project, so the turn-end check (stop.sh) names
# it — or stays quiet. Silent on any failure — a hook must never get in the way.

. "$(dirname "$0")/lib.sh"
# Devin has no plugin setting a hook can read, so the token and address come from the environment.
token="$SEAMTRAIL_TOKEN"
url="${SEAMTRAIL_URL:-https://mcp.seamtrail.com/mcp}"
input=$(cat)

session=$(printf '%s' "$input" | grep -o '"session_id"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
# SEAM-230: the chat's custom name, when the assistant gives one (Devin's hook input names none, so usually empty).
title=$(printf '%s' "$input" | grep -o '"session_title"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
# A new (or resumed) chat starts clean: nothing saved yet, no project known yet.
if [ -n "$session" ]; then rm -f "$data/saved-$session" "$data/project-$session"; fi

[ -z "$token" ] && exit 0
dir="${DEVIN_PROJECT_DIR:-${CLAUDE_PROJECT_DIR:-$PWD}}"
remote=$(git -C "$dir" remote get-url origin 2>/dev/null)
branch=$(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null)

tmp=$(mktemp -d 2>/dev/null) || exit 0
# SEAM-273: this plugin's own version, from its manifest, so SeamTrail can tell this chat when a newer one is out.
version=$(sed -n 's/^[[:space:]]*"version"[[:space:]]*:[[:space:]]*"\([0-9.]*\)".*/\1/p' "$(dirname "$0")/../.devin-plugin/plugin.json" 2>/dev/null | head -1)
if curl -s -f -G --max-time 10 "${url%/}/hook/start" \
  -H "Authorization: Bearer $token" \
  --data-urlencode "remote=$remote" \
  --data-urlencode "branch=$branch" \
  --data-urlencode "chat=$session" \
  --data-urlencode "chatName=$title" \
  --data-urlencode "folder=$dir" \
  --data-urlencode "assistant=devin" \
  --data-urlencode "version=$version" \
  -D "$tmp/headers" -o "$tmp/body" 2>/dev/null; then
  context SessionStart < "$tmp/body"
  project=$(grep -i '^x-seamtrail-project:' "$tmp/headers" | head -1 | sed 's/^[^:]*:[[:space:]]*//' | tr -d '\r')
  name=$(grep -i '^x-seamtrail-project-name:' "$tmp/headers" | head -1 | sed 's/^[^:]*:[[:space:]]*//' | tr -d '\r')
  if [ -n "$session" ] && [ -n "$project" ]; then
    mkdir -p "$data" && printf '%s\n%s\n' "$project" "$name" > "$data/project-$session"
  fi
fi
rm -rf "$tmp"
exit 0
