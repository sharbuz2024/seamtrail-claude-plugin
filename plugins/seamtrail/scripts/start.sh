#!/bin/sh
# SeamTrail · chat start (SEAM-215). Hands the agent this folder's project context: SeamTrail matches the git
# remote and branch to the person's project and answers with plain text, which Claude Code adds to the chat.
# It also keeps, on this computer, which project it found, so the turn-end check (stop.sh) names that project —
# or asks which one, or stays quiet when the folder is no SeamTrail project.
# Silent on any failure — a hook must never get in the way.

token="${CLAUDE_PLUGIN_OPTION_SEAMTRAIL_TOKEN:-$SEAMTRAIL_TOKEN}"
url="${CLAUDE_PLUGIN_OPTION_SEAMTRAIL_URL:-${SEAMTRAIL_URL:-https://mcp.seamtrail.com/mcp}}"
input=$(cat)
data="$CLAUDE_PLUGIN_DATA"

session=$(printf '%s' "$input" | grep -o '"session_id"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
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
