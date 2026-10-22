#!/bin/sh
# SeamTrail · the person picked this chat's project (SEAM-255; the Claude Code plugin's picked.sh — SEAM-228 — for
# VS Code): set_chat_project was called, so the turn-end check (stop.sh) names that project from now on — or, for
# "No project", stays quiet. VS Code drops a hook's matcher, so this runs after every tool and checks the tool's name
# itself. Nothing leaves the computer.

input=$(cat)
# Most calls are to other tools: done at once (no process started) unless the input names SeamTrail anywhere.
case "$input" in *[Ss][Ee][Aa][Mm][Tt][Rr][Aa][Ii][Ll]*) ;; *) exit 0 ;; esac
. "$(dirname "$0")/lib.sh"
[ -n "$session" ] || exit 0
is_tool set_chat_project || exit 0
# Refused (a project the person is not on, or both answers at once): nothing changed.
failed && exit 0

# The project id from the call's arguments, which come before its result; the Copilot harness may hand them over as a
# JSON string, so its quotes may be escaped: \"projectId\":\"…\". An id in the result alone ("No project") is not one.
args=$(printf '%s' "$input" | LC_ALL=C tr '\n' ' ' | LC_ALL=C sed -E 's/"(toolResult|tool_result|tool_response)"[[:space:]]*:.*$//')
project=$(printf '%s' "$args" | LC_ALL=C grep -oE '\\?"projectId\\?"[[:space:]]*:[[:space:]]*\\?"[0-9a-fA-F-]{36}\\?"' | head -1 | grep -oE '[0-9a-fA-F-]{36}')
if [ -n "$project" ]; then
  mkdir -p "$data" && printf '%s\n\n' "$project" > "$data/project-$session"
else
  rm -f "$data/project-$session"
fi
exit 0
