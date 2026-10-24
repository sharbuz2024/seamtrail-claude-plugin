#!/bin/sh
# SeamTrail · at every message (SEAM-233). Asks SeamTrail what this chat should know with the message the person just
# sent — what is new on the chat's work since it last looked, the latest still-true memory about the tickets the message
# names, and (founder 2026-10-24: "just make sure no secrets and credentials") what the message is about: the task, the
# document and the decisions its words point to — and hands it to Claude with the message. Adds nothing when there is
# nothing to tell. Silent on any failure — a hook must never get in the way.
#
# What leaves this computer: the chat id, the ticket numbers, and a search hint cut from the message HERE, before it is
# sent — code blocks, secrets and credentials taken out (hint-rules.json), then the message itself when short, else its
# first 300 and last 200 characters and its links. It goes in the request body (never in the address, which servers
# log); SeamTrail uses it to search by meaning and does not keep it. Cleaning needs node or python3: without either,
# no words of the message are sent — only the chat id and the ticket numbers, as before.

token="${CLAUDE_PLUGIN_OPTION_SEAMTRAIL_TOKEN:-$SEAMTRAIL_TOKEN}"
url="${CLAUDE_PLUGIN_OPTION_SEAMTRAIL_URL:-${SEAMTRAIL_URL:-https://mcp.seamtrail.com/mcp}}"
[ -n "$token" ] || exit 0
input=$(cat)
session=$(printf '%s' "$input" | grep -o '"session_id"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
[ -n "$session" ] || exit 0
here=$(dirname "$0")

# The cleaned body {chat, tickets, hint}, from node, else python3 (not macOS's stand-in without the developer tools,
# which would open an install window).
body=""
if command -v node >/dev/null 2>&1; then
  body=$(printf '%s' "$input" | node "$here/hint.js" "$here/hint-rules.json" 2>/dev/null)
else
  py=$(command -v python3 2>/dev/null)
  if [ -n "$py" ] && ! { [ "$(uname)" = Darwin ] && [ "$py" = /usr/bin/python3 ] && ! xcode-select -p >/dev/null 2>&1; }; then
    body=$(printf '%s' "$input" | "$py" -I "$here/hint.py" "$here/hint-rules.json" 2>/dev/null)
  fi
fi

if [ -n "$body" ]; then
  tmp=$(mktemp 2>/dev/null) || exit 0
  code=$(printf '%s' "$body" | curl -s --max-time 4 -X POST "${url%/}/hook/message" \
    -H "Authorization: Bearer $token" -H 'Content-Type: application/json' --data-binary @- \
    -o "$tmp" -w '%{http_code}' 2>/dev/null)
  case "$code" in
    2??) cat "$tmp"; rm -f "$tmp"; exit 0 ;;
    404|405) rm -f "$tmp" ;; # an older SeamTrail without the hint: ask the way it knows, below
    *) rm -f "$tmp"; exit 0 ;;
  esac
fi

# Without node or python3, or an older SeamTrail: the chat id and the ticket numbers in the message ("PAY-4"), at most
# five; no JSON tool needed.
prompt=$(printf '%s' "$input" | sed -n 's/.*"prompt"[[:space:]]*:[[:space:]]*"\(.*\)".*/\1/p' | head -c 20000)
# Not after another capital or digit; a lowercase letter may come before ("\nPAY-4" in the hook's JSON).
tickets=$(printf '%s' "$prompt" | grep -oE '(^|[^A-Z0-9])[A-Z][A-Z0-9]{1,9}-[0-9]{1,7}' \
  | sed 's/^[^A-Z]//' | sort -u | head -5 | paste -sd, -)

curl -s -f -G --max-time 4 "${url%/}/hook/message" \
  -H "Authorization: Bearer $token" \
  --data-urlencode "chat=$session" \
  --data-urlencode "tickets=$tickets" 2>/dev/null
exit 0
