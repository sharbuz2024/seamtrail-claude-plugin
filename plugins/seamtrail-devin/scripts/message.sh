#!/bin/sh
# SeamTrail · at every message, in the Devin CLI (SEAM-254: the Claude Code plugin's message.sh — SEAM-233 — in Devin's
# hook format). Asks SeamTrail what this chat should know with the message the person just sent — what is new on the
# chat's work since it last looked, and the latest still-true memory about the tickets the message names — and hands
# it to Devin with the message (as JSON: hookSpecificOutput.additionalContext). Sends only the chat id and the ticket
# numbers in the message, never its words. Adds nothing when there is nothing to tell. Silent on any failure — a hook
# must never get in the way.

. "$(dirname "$0")/lib.sh"
token="$SEAMTRAIL_TOKEN"
url="${SEAMTRAIL_URL:-https://mcp.seamtrail.com/mcp}"
[ -n "$token" ] || exit 0
input=$(cat)
session=$(printf '%s' "$input" | grep -o '"session_id"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
[ -n "$session" ] || exit 0

# The ticket numbers in the message ("PAY-4"), at most five; no JSON tool needed. The message is cut at its own closing
# quote: Devin's hook input has more fields after it (prompt_id), which must not count as the message.
prompt=$(printf '%s' "$input" | LC_ALL=C sed -nE 's/.*"prompt"[[:space:]]*:[[:space:]]*"(([^"\\]|\\.)*)".*/\1/p' | head -c 20000)
# Not after another capital or digit; a lowercase letter may come before ("\nPAY-4" in the hook's JSON).
tickets=$(printf '%s' "$prompt" | LC_ALL=C grep -oE '(^|[^A-Z0-9])[A-Z][A-Z0-9]{1,9}-[0-9]{1,7}' \
  | sed 's/^[^A-Z]//' | sort -u | head -5 | paste -sd, -)

curl -s -f -G --max-time 4 "${url%/}/hook/message" \
  -H "Authorization: Bearer $token" \
  --data-urlencode "chat=$session" \
  --data-urlencode "tickets=$tickets" 2>/dev/null | context UserPromptSubmit
exit 0
