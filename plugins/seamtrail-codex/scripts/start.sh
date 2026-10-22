#!/bin/sh
# SeamTrail · chat start, in Codex (SEAM-252; the Claude Code plugin's start.sh, SEAM-215, SEAM-230, SEAM-228). Codex
# runs it at SessionStart (startup, resume, clear, compact, fork — never for a subagent). Registers this chat with
# SeamTrail (its id and folder; Codex gives a chat no name here), so the chat id the guard adds to SeamTrail calls is
# believed, and says it is a Codex chat (assistant=codex), so SeamTrail words its project question for Codex. SeamTrail
# answers with plain text, which Codex adds to the chat as developer context: the context of the project the person
# picked for this chat, or, not picked yet, the question to ask at the first message ("Which SeamTrail project is this
# chat for?" — the git remote and branch only order its options). It also keeps, on this computer, the chat's project,
# so the turn-end check (stop.sh) names it — or stays quiet. Silent on any failure — a hook must never get in the way.

token="$SEAMTRAIL_TOKEN"
url="${SEAMTRAIL_URL:-https://mcp.seamtrail.com/mcp}"
input=$(cat)
# Codex's plugin data folder (~/.codex/plugins/data/<plugin>-<marketplace>); Codex does not create it.
data="${PLUGIN_DATA:-${XDG_STATE_HOME:-$HOME/.local/state}/seamtrail/codex}"

session=$(printf '%s' "$input" | grep -o '"session_id"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
# A new (or resumed) chat starts clean: nothing saved yet, no project known yet.
if [ -n "$session" ]; then rm -f "$data/saved-$session" "$data/project-$session"; fi

[ -z "$token" ] && exit 0
# The session's folder, from the hook's input (Codex also runs the hook in it).
dir=$(printf '%s' "$input" | grep -o '"cwd"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
[ -n "$dir" ] && [ -d "$dir" ] || dir="$PWD"
remote=$(git -C "$dir" remote get-url origin 2>/dev/null)
branch=$(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null)

tmp=$(mktemp -d 2>/dev/null) || exit 0
if curl -s -f -G --max-time 10 "${url%/}/hook/start" \
  -H "Authorization: Bearer $token" \
  --data-urlencode "assistant=codex" \
  --data-urlencode "remote=$remote" \
  --data-urlencode "branch=$branch" \
  --data-urlencode "chat=$session" \
  --data-urlencode "folder=$dir" \
  -D "$tmp/headers" -o "$tmp/body" 2>/dev/null; then
  cat "$tmp/body"
  project=$(grep -i '^x-seamtrail-project:' "$tmp/headers" | head -1 | sed 's/^[^:]*:[[:space:]]*//' | tr -d '\r')
  name=$(grep -i '^x-seamtrail-project-name:' "$tmp/headers" | head -1 | sed 's/^[^:]*:[[:space:]]*//' | tr -d '\r')
  if [ -n "$session" ] && [ -n "$project" ]; then
    mkdir -p "$data" && printf '%s\n%s\n' "$project" "$name" > "$data/project-$session"
  fi
fi
rm -rf "$tmp"
exit 0
