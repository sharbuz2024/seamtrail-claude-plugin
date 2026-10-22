#!/bin/sh
# SeamTrail for Kiro · the person picked this chat's project (SEAM-264; the Claude Code plugin's picked.sh, SEAM-228).
# Kiro's PostToolUse hook after set_chat_project: the turn-end check (stop.sh) names that project from now on — or, for
# "No project", stays quiet. Kiro's hook input may carry the call's arguments empty, and a refusal only in words, so the
# outcome is read from SeamTrail's answer: "project": {"id": …} (a project) or "project": null ("No project"). An input
# with no answer in it falls back to the call's own projectId, as in Claude Code. Nothing leaves the computer.

input=$(cat)
data="${XDG_STATE_HOME:-$HOME/.local/state}/seamtrail/kiro"
session=$(printf '%s' "$input" | grep -o '"session_id"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
case "$session" in *[!A-Za-z0-9_-]*) session="" ;; esac
[ -n "$session" ] || exit 0
tool=$(printf '%s' "$input" | grep -o '"tool_name"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"\([^"]*\)"$/\1/' | tr 'A-Z' 'a-z')
case "$tool" in *seamtrail*set_chat_project) ;; *) exit 0 ;; esac
# Refused (a project the person is not on, or both answers at once): nothing changed.
printf '%s' "$input" | grep -q '"isError"[[:space:]]*:[[:space:]]*true' && exit 0
printf '%s' "$input" | grep -q '"success"[[:space:]]*:[[:space:]]*false' && exit 0

# SeamTrail's answer, as text inside the hook's JSON: its quotes may be escaped and its lines written \n.
said=$(printf '%s' "$input" | grep -oE '\\?"project\\?"[[:space:]]*:[[:space:]]*(null|\{(\\n|[[:space:]])*\\?"id\\?"[[:space:]]*:[[:space:]]*\\?"[0-9a-fA-F-]{36})' | head -1)
if [ -z "$said" ]; then
  # An answer that says neither (a refusal in words) changed nothing.
  printf '%s' "$input" | grep -Eq '"tool_response"[[:space:]]*:[[:space:]]*("[^"]|\{|\[)' && exit 0
  # No answer to read: the call's own projectId, as in Claude Code; without one, "No project".
  said=$(printf '%s' "$input" | grep -o '"projectId"[[:space:]]*:[[:space:]]*"[0-9a-fA-F-]\{36\}"' | head -1)
  [ -n "$said" ] || said=null
fi

case "$said" in
  *null) rm -f "$data/project-$session" ;;
  *)
    project=$(printf '%s' "$said" | grep -oE '[0-9a-fA-F-]{36}' | tail -1)
    [ -n "$project" ] && mkdir -p "$data" && printf '%s\n\n' "$project" > "$data/project-$session"
    ;;
esac
exit 0
