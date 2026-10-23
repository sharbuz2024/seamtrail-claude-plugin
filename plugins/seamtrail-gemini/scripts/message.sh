#!/bin/sh
# SeamTrail · at every message (SEAM-253: the Claude Code plugin's message.sh, for Gemini CLI's BeforeAgent). Asks
# SeamTrail what this chat should know with the message the person just sent — what is new on the chat's work since it
# last looked, and the latest still-true memory about the tickets the message names — and hands it to Gemini with the
# message. Sends the chat id, the ticket numbers in the message and a search hint cut from the message on this computer first (hint.sh: no code blocks, secrets or credentials; SEAM-233); without node or python3, never its words. Adds nothing when there is
# nothing to tell. The person's message also starts a new turn: nothing saved in it yet, not asked yet (stop.sh). And it
# hands over the chat-start context Gemini CLI could not take at /clear or after compressing the chat (start.sh).
# Silent on any failure — a hook must never get in the way.

. "$(dirname "$0")/common.sh"
[ -n "$session" ] || exit 0

prompt=$(printf '%s' "$input" | sed -n 's/.*"prompt"[[:space:]]*:[[:space:]]*"\(.*\)".*/\1/p' | head -c 20000)
# The turn-end reminder comes back as a prompt (Gemini CLI retries the turn with it): not the person's message, and the
# turn goes on.
case "$prompt" in *"$reminder"*) exit 0 ;; esac
rm -f "$data/saved-$session" "$data/asked-$session"

start=""
[ -s "$data/start-$session" ] && start=$(cat "$data/start-$session")
rm -f "$data/start-$session"

news=""
if [ -n "$token" ]; then
  # The ticket numbers in the message ("PAY-4"), at most five; no JSON tool needed.
  # Not after another capital or digit; a lowercase letter may come before ("\nPAY-4" in the hook's JSON).
  tickets=$(printf '%s' "$prompt" | grep -oE '(^|[^A-Z0-9])[A-Z][A-Z0-9]{1,9}-[0-9]{1,7}' \
    | sed 's/^[^A-Z]//' | sort -u | head -5 | paste -sd, -)
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
  news="$answer"
fi

if [ -n "$start" ] && [ -n "$news" ]; then
  printf '%s\n\n%s\n' "$start" "$news" | context BeforeAgent
else
  printf '%s%s\n' "$start" "$news" | context BeforeAgent
fi
exit 0
