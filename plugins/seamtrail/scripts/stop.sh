#!/bin/sh
# SeamTrail · turn end (SEAM-215). When nothing was saved to SeamTrail this turn, the agent is asked once to
# remember what was decided, learned or blocked — or to finish if nothing was. The agent saves; no chat text is
# sent anywhere by this hook.

input=$(cat)
session=$(printf '%s' "$input" | grep -o '"session_id"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
flag="$CLAUDE_PLUGIN_DATA/saved-$session"

# Saved this turn: finish, and start the next turn clean.
if [ -n "$CLAUDE_PLUGIN_DATA" ] && [ -n "$session" ] && [ -f "$flag" ]; then
  rm -f "$flag"
  exit 0
fi
# Asked once already this turn: never twice.
printf '%s' "$input" | grep -q '"stop_hook_active"[[:space:]]*:[[:space:]]*true' && exit 0
# Not set up (no key): SeamTrail cannot save anything, so do not ask.
[ -z "${CLAUDE_PLUGIN_OPTION_SEAMTRAIL_TOKEN:-$SEAMTRAIL_TOKEN}" ] && exit 0

printf '%s\n' '{"decision":"block","reason":"SeamTrail: nothing was saved this turn. If in this turn your person decided something, learned a fact, hit or cleared a blocker, raised a risk, asked an open question or changed a status, call the SeamTrail remember tool now: one plain sentence each, with kind and subject, a decision with its reason. If none of that happened, finish now without saying anything more."}'
exit 0
