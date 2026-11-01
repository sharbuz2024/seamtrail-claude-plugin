#!/bin/sh
# SeamTrail for Kiro · at every message (SEAM-264; the Claude Code plugin's message.sh, SEAM-233). Kiro's UserPromptSubmit
# hook asks SeamTrail what this chat should know with the message the person just sent — what is new on the chat's work
# since it last looked, and the latest still-true memory about the tickets the message names — and hands it to the
# agent: Kiro adds what a UserPromptSubmit command prints to the agent's context. Sends the chat id, the ticket
# numbers in the message and a search hint cut from the message on this computer first (hint.sh: no code blocks, secrets or credentials; SEAM-233); without node or python3, never its words. Adds nothing when there is nothing to tell.
# For Kiro also: a chat Kiro started without
# its SessionStart hook is registered here first (start.sh). Silent on any failure — a hook must never get in the way.

input=$(cat)
data="${XDG_STATE_HOME:-$HOME/.local/state}/seamtrail/kiro"
session=$(printf '%s' "$input" | grep -o '"session_id"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
case "$session" in *[!A-Za-z0-9_-]*) session="" ;; esac
[ -n "$session" ] || exit 0

# The person's message: the hook's "prompt", still escaped as JSON (Kiro IDE 0.x gave it in USER_PROMPT instead).
prompt=$(printf '%s' "$input" | sed -n -E 's/.*"prompt"[[:space:]]*:[[:space:]]*"(([^"\\]|\\.)*)".*/\1/p' | head -c 20000)
[ -n "$prompt" ] || prompt=$(printf '%s' "$USER_PROMPT" | head -c 20000)
# Kiro started this chat without its SessionStart hook: register it now; its text goes with this message.
[ -f "$data/started-$session" ] || printf '%s' "$input" | sh "$(dirname "$0")/start.sh"

token="$SEAMTRAIL_TOKEN"
url="${SEAMTRAIL_URL:-https://mcp.seamtrail.com/mcp}"
[ -n "$token" ] || exit 0
# The ticket numbers in the message ("PAY-4"), at most five; no JSON tool needed.
# Not after another capital or digit; a lowercase letter may come before ("\nPAY-4" in the hook's JSON).
tickets=$(printf '%s' "$prompt" | grep -oE '(^|[^A-Z0-9])[A-Z][A-Z0-9]{1,9}-[0-9]{1,7}' \
  | sed 's/^[^A-Z]//' | sort -u | head -5 | paste -sd, -)

# Only the hook's own "prompt" (still escaped as JSON) is cleaned and sent; Kiro IDE 0.x's USER_PROMPT is not.
said=$(printf '%s' "$input" | sed -n -E 's/.*"prompt"[[:space:]]*:[[:space:]]*"(([^"\\]|\\.)*)".*/\1/p' | head -c 20000)
# SEAM-233 (founder 2026-10-24: "just make sure no secrets and credentials"): what the message is about goes too — cut
# from it on this computer first by hint.sh (no code blocks, secrets or credentials), in the request body, never the
# address. Without node or python3, or with an older SeamTrail, only the chat id and the ticket numbers, as before.
body=""
[ -n "$said" ] && body=$(sh "$(dirname "$0")/hint.sh" "$session" "$said")
answer="" code=""
if [ -n "$body" ] && tmp=$(mktemp 2>/dev/null); then
  code=$(printf '%s' "$body" | curl -s --max-time 4 -X POST "${url%/}/hook/message" \
    -H "Authorization: Bearer $token" -H 'Content-Type: application/json' --data-binary @- \
    -o "$tmp" -w '%{http_code}' 2>/dev/null)
  case "$code" in 2??) answer=$(cat "$tmp") ;; esac
  rm -f "$tmp"
fi
case "$code" in
  2??) ;;
  ""|404|405)
    answer=$(curl -s -f -G --max-time 4 "${url%/}/hook/message" \
      -H "Authorization: Bearer $token" \
      --data-urlencode "chat=$session" \
      --data-urlencode "tickets=$tickets" 2>/dev/null) ;;
esac
# SEAM-215: the save reminder, when the last turn saved nothing, goes with this message (remind.sh).
note=$(sh "$(dirname "$0")/remind.sh" "$data" "$session")
if [ -n "$answer" ] && [ -n "$note" ]; then printf '%s\n\n%s' "$answer" "$note"; else printf '%s%s' "$answer" "$note"; fi
exit 0
