#!/bin/sh
# SeamTrail · chat start (SEAM-253: the Claude Code plugin's start.sh, for Gemini CLI's SessionStart). Registers this
# chat with SeamTrail (its id and folder, and that it is a Gemini CLI chat), so the chat id the guard adds to SeamTrail
# calls is believed. SeamTrail answers with plain text, which goes to Gemini as context: the context of the project the
# person picked for this chat, or, not picked yet, the question Gemini asks at the first message ("Which SeamTrail
# project is this chat for?" — the git remote and branch only order its options). It also keeps, on this computer, the
# chat's project, so the turn-end check (stop.sh) names it — or stays quiet.
# Two Gemini CLI gaps it covers: after /clear, Gemini CLI does not give a SessionStart hook's context to the new chat;
# and compressing a long chat (PreCompress, which runs this script too) folds the start context into a summary. Then
# the answer is kept here and handed over with the person's next message (message.sh), as at a chat start.
# Silent on any failure — a hook must never get in the way.

. "$(dirname "$0")/common.sh"

event=$(field hook_event_name)
from=$(field source)
# A new, resumed or cleared chat starts clean: nothing saved yet, no project known yet, not asked yet.
if [ "$event" != PreCompress ] && [ -n "$session" ]; then
  rm -f "$data/saved-$session" "$data/project-$session" "$data/asked-$session" "$data/start-$session"
fi
# Gemini CLI never empties this folder (not even when the extension is removed): what is a month old goes. A chat
# that comes back later gets its project from SeamTrail again, right here.
find "$data" -type f -mtime +30 -exec rm -f {} + 2>/dev/null

[ -n "$token" ] || exit 0
dir="${GEMINI_PROJECT_DIR:-$PWD}"
remote=$(git -C "$dir" remote get-url origin 2>/dev/null)
branch=$(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null)

tmp=$(mktemp -d 2>/dev/null) || exit 0
# SEAM-273: this plugin's own version, from its manifest, so SeamTrail can tell this chat when a newer one is out.
version=$(sed -n 's/^[[:space:]]*"version"[[:space:]]*:[[:space:]]*"\([0-9.]*\)".*/\1/p' "$(dirname "$0")/../gemini-extension.json" 2>/dev/null | head -1)
if curl -s -f -G --max-time 10 "${url%/}/hook/start" \
  -H "Authorization: Bearer $token" \
  --data-urlencode "assistant=gemini" \
  --data-urlencode "version=$version" \
  --data-urlencode "remote=$remote" \
  --data-urlencode "branch=$branch" \
  --data-urlencode "chat=$session" \
  --data-urlencode "folder=$dir" \
  -D "$tmp/headers" -o "$tmp/body" 2>/dev/null; then
  project=$(grep -i '^x-seamtrail-project:' "$tmp/headers" | head -1 | sed 's/^[^:]*:[[:space:]]*//' | tr -d '\r')
  name=$(grep -i '^x-seamtrail-project-name:' "$tmp/headers" | head -1 | sed 's/^[^:]*:[[:space:]]*//' | tr -d '\r')
  if [ -n "$session" ] && [ -n "$project" ]; then
    mkdir -p "$data" && printf '%s\n%s\n' "$project" "$name" > "$data/project-$session"
  fi
  if [ "$event" = SessionStart ] && [ "$from" != clear ]; then
    context SessionStart < "$tmp/body"
  elif [ -n "$session" ] && [ -s "$tmp/body" ]; then
    mkdir -p "$data" && cp "$tmp/body" "$data/start-$session"
  fi
fi
rm -rf "$tmp"
exit 0
