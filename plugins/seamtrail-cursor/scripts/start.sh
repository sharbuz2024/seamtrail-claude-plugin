#!/bin/sh
# SeamTrail · chat start (SEAM-215, SEAM-230, SEAM-228) — for Cursor (SEAM-256), on sessionStart. Registers this chat
# with SeamTrail (its id and folder, and that it is a Cursor chat), so the chat id the guard adds to SeamTrail calls is
# believed. SeamTrail answers with plain text, which goes to the agent as the chat's context (additional_context): the
# context of the project the person picked for this chat, or, not picked yet, the question the agent asks at the first
# message ("Which SeamTrail project is this chat for?" — the git remote and branch only order its options). It also
# keeps, on this computer, the chat's project, so the turn-end check (stop.sh) names it — or stays quiet.
#
# It also tells the rest of the chat's hooks where this plugin is (env SEAMTRAIL_CURSOR_ROOT): Cursor runs the
# turn-end hook from the workspace, and that hook uses this folder only if CURSOR_PLUGIN_ROOT is empty there.
# The token: env SEAMTRAIL_TOKEN (Cursor has no per-person plugin setting that hooks can read). Silent on any failure —
# a hook must never get in the way.

lib="$(dirname "$0")/lib.sh"
[ -f "$lib" ] || exit 0
. "$lib"

token="$SEAMTRAIL_TOKEN"
url="${SEAMTRAIL_URL:-https://mcp.seamtrail.com/mcp}"
input=$(cat)
chat=$(st_chat "$input")
root=$(CDPATH='' cd -- "$(dirname "$0")/.." 2>/dev/null && pwd)

# A new chat starts clean: nothing saved yet, no project known yet. Notes older than 60 days go.
if mkdir -p "$st_state" 2>/dev/null; then
  [ -n "$chat" ] && rm -f "$st_state/saved-$chat" "$st_state/project-$chat" "$st_state/reminded-$chat" "$st_state/asked-$chat"
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
      -D "$tmp/headers" -o "$tmp/body" 2>/dev/null; then
      text=$(cat "$tmp/body")
      project=$(grep -i '^x-seamtrail-project:' "$tmp/headers" | head -n 1 | sed 's/^[^:]*:[[:space:]]*//' | tr -d '\r')
      name=$(grep -i '^x-seamtrail-project-name:' "$tmp/headers" | head -n 1 | sed 's/^[^:]*:[[:space:]]*//' | tr -d '\r')
      if [ -n "$chat" ] && [ -n "$project" ]; then
        printf '%s\n%s\n' "$project" "$name" > "$st_state/project-$chat"
      fi
    fi
    rm -rf "$tmp"
  fi
fi

# Cursor reads one JSON object: the session's env for later hooks, and the text for the agent.
out=""
[ -n "$root" ] && out="\"env\":{\"SEAMTRAIL_CURSOR_ROOT\":$(st_json "$root")}"
if [ -n "$text" ]; then
  [ -n "$out" ] && out="$out,"
  out="$out\"additional_context\":$(st_json "$text")"
fi
printf '{%s}\n' "$out"
exit 0
