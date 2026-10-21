#!/bin/sh
# SeamTrail · chat start (SEAM-215). Hands the agent this folder's project context: SeamTrail matches the git
# remote and branch to the person's project and answers with plain text, which Claude Code adds to the chat.
# Silent on any failure — a hook must never get in the way.

token="${CLAUDE_PLUGIN_OPTION_SEAMTRAIL_TOKEN:-$SEAMTRAIL_TOKEN}"
url="${CLAUDE_PLUGIN_OPTION_SEAMTRAIL_URL:-${SEAMTRAIL_URL:-https://mcp.seamtrail.com/mcp}}"
input=$(cat)

# A new chat starts with nothing saved yet (see stop.sh).
session=$(printf '%s' "$input" | grep -o '"session_id"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
if [ -n "$CLAUDE_PLUGIN_DATA" ] && [ -n "$session" ]; then rm -f "$CLAUDE_PLUGIN_DATA/saved-$session"; fi

[ -z "$token" ] && exit 0
dir="${CLAUDE_PROJECT_DIR:-$PWD}"
remote=$(git -C "$dir" remote get-url origin 2>/dev/null)
branch=$(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null)

curl -s -f -G --max-time 10 "${url%/}/hook/start" \
  -H "Authorization: Bearer $token" \
  --data-urlencode "remote=$remote" \
  --data-urlencode "branch=$branch" 2>/dev/null
exit 0
