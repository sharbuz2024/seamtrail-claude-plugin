#!/bin/sh
# SeamTrail · a message's search hint, cleaned on this computer (SEAM-233; founder 2026-10-24: "just make sure no secrets
# and credentials"; the Claude Code plugin's message.sh does the same). Arguments: the chat id, and the message as it
# sits in the hook's JSON (still escaped). Prints the body {chat, tickets, hint} for SeamTrail — code blocks, secrets
# and credentials cut out by hint.js (node) or hint.py (python3) with hint-rules.json — or nothing: no node or python3
# (not macOS's stand-in without the developer tools, which would open an install window), or a message it could not
# read. Then no words of the message are sent.
here=$(dirname "$0")
input=$(printf '{"session_id":"%s","prompt":"%s"}' "$1" "$2")
if command -v node >/dev/null 2>&1; then
  printf '%s' "$input" | node "$here/hint.js" "$here/hint-rules.json" 2>/dev/null
  exit 0
fi
py=$(command -v python3 2>/dev/null)
[ -n "$py" ] || exit 0
if [ "$(uname)" = Darwin ] && [ "$py" = /usr/bin/python3 ] && ! xcode-select -p >/dev/null 2>&1; then exit 0; fi
printf '%s' "$input" | "$py" -I "$here/hint.py" "$here/hint-rules.json" 2>/dev/null
exit 0
