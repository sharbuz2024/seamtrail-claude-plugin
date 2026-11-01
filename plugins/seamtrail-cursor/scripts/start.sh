#!/bin/sh
# SeamTrail · chat start (SEAM-215, SEAM-230, SEAM-228) — for Cursor (SEAM-256), on sessionStart. Registers this chat
# with SeamTrail (its id and folder, and that it is a Cursor chat), so the chat id the guard adds to SeamTrail calls is
# believed. SeamTrail answers with plain text, which goes to the agent as the chat's context (additional_context): the
# context of the project the person picked for this chat, or, not picked yet, the question the agent asks at the first
# message ("Which SeamTrail project is this chat for?" — the git remote and branch only order its options).
#
# The token: env SEAMTRAIL_TOKEN (Cursor has no per-person plugin setting that hooks can read). Silent on any failure —
# a hook must never get in the way.

lib="$(dirname "$0")/lib.sh"
[ -f "$lib" ] || exit 0
. "$lib"

token="$SEAMTRAIL_TOKEN"
url="${SEAMTRAIL_URL:-https://mcp.seamtrail.com/mcp}"
input=$(cat)
chat=$(st_chat "$input")

# Notes older than 60 days go.
if mkdir -p "$st_state" 2>/dev/null; then
  find "$st_state" -type f -mtime +60 -exec rm -f {} + 2>/dev/null
fi

text=""
if [ -n "$token" ]; then
  # The workspace folder: Cursor's CURSOR_PROJECT_DIR, else the first of the input's workspace_roots.
  dir="${CURSOR_PROJECT_DIR:-$CLAUDE_PROJECT_DIR}"
  [ -n "$dir" ] || dir=$(printf '%s' "$input" | sed -n 's/.*"workspace_roots"[[:space:]]*:[[:space:]]*\[[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)
  remote=""
  branch=""
  if [ -n "$dir" ]; then
    remote=$(git -C "$dir" remote get-url origin 2>/dev/null)
    branch=$(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null)
  fi
  tmp=$(mktemp -d 2>/dev/null) || tmp=""
  if [ -n "$tmp" ]; then
    # SEAM-273: this plugin's own version, from its manifest, so SeamTrail can tell this chat when a newer one is out.
    version=$(sed -n 's/^[[:space:]]*"version"[[:space:]]*:[[:space:]]*"\([0-9.]*\)".*/\1/p' "$(dirname "$0")/../.cursor-plugin/plugin.json" 2>/dev/null | head -1)
    if curl -s -f -G --max-time 10 "${url%/}/hook/start" \
      -H "Authorization: Bearer $token" \
      --data-urlencode "remote=$remote" \
      --data-urlencode "branch=$branch" \
      --data-urlencode "chat=$chat" \
      --data-urlencode "folder=$dir" \
      --data-urlencode "assistant=cursor" \
      --data-urlencode "version=$version" \
      -o "$tmp/body" 2>/dev/null; then
      text=$(cat "$tmp/body")
    fi
    rm -rf "$tmp"
  fi
fi

# Cursor reads one JSON object: the text for the agent.
out=""
[ -n "$text" ] && out="\"additional_context\":$(st_json "$text")"
printf '{%s}\n' "$out"
exit 0
