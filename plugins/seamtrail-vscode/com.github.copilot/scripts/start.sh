#!/bin/sh
# SeamTrail · chat start (SEAM-255; the Claude Code plugin's start.sh — SEAM-215, SEAM-230, SEAM-228, SEAM-256 — for
# VS Code). Registers this chat with SeamTrail (its id and folder, and that it is a VS Code chat: assistant=vscode), so
# the chat id the guard adds to SeamTrail calls is believed. SeamTrail answers with plain text, which this hook hands to
# the agent as the chat's context (VS Code takes context only as JSON): the context of the project the person picked
# for this chat, or, not picked yet, the question to ask at the first message ("Which SeamTrail project is this chat
# for?" — the git remote and branch only order its options). It also keeps, on this computer, the chat's project, so
# the turn-end check (stop.sh) names it — or stays quiet. VS Code gives a hook no chat name, so none is sent.
# Silent on any failure — a hook must never get in the way.

input=$(cat)
. "$(dirname "$0")/lib.sh"

# A new (or resumed) chat starts clean: nothing saved yet, no project known yet.
if [ -n "$session" ]; then rm -f "$data/saved-$session" "$data/project-$session"; fi

[ -z "$token" ] && exit 0
# The workspace folder VS Code runs the chat in.
dir=$(field cwd)
if [ -z "$dir" ] || [ ! -d "$dir" ]; then dir="$PWD"; fi
remote=$(git -C "$dir" remote get-url origin 2>/dev/null)
branch=$(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null)

tmp=$(mktemp -d 2>/dev/null) || exit 0
if curl -s -f -G --max-time 10 "${url%/}/hook/start" \
  -H "Authorization: Bearer $token" \
  --data-urlencode "remote=$remote" \
  --data-urlencode "branch=$branch" \
  --data-urlencode "chat=$session" \
  --data-urlencode "folder=$dir" \
  --data-urlencode "assistant=vscode" \
  -D "$tmp/headers" -o "$tmp/body" 2>/dev/null; then
  if [ -s "$tmp/body" ]; then
    text=$(json_string < "$tmp/body")
    if camel; then
      printf '{"additionalContext":%s}\n' "$text"
    else
      printf '{"additionalContext":%s,"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":%s}}\n' "$text" "$text"
    fi
  fi
  project=$(grep -i '^x-seamtrail-project:' "$tmp/headers" | head -1 | sed 's/^[^:]*:[[:space:]]*//' | tr -d '\r')
  name=$(grep -i '^x-seamtrail-project-name:' "$tmp/headers" | head -1 | sed 's/^[^:]*:[[:space:]]*//' | tr -d '\r')
  if [ -n "$session" ] && [ -n "$project" ]; then
    mkdir -p "$data" && printf '%s\n%s\n' "$project" "$name" > "$data/project-$session"
  fi
fi
rm -rf "$tmp"
exit 0
