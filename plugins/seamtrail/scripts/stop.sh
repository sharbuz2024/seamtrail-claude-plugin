#!/bin/sh
# SeamTrail · turn end (SEAM-215, SEAM-228). Only in a chat with a SeamTrail project — the one its person picked, known
# at chat start (start.sh) or when they pick it (picked.sh); an older SeamTrail matched it from the folder: when
# nothing was saved to SeamTrail this turn (a note, or a change SeamTrail made — saved.sh), this notes it on this
# computer (remind-<chat>), and with the person's next message remind.sh asks the agent once to remember what this turn
# decided, learned or blocked — into that project, named. No project: never reminds. No chat text is sent anywhere by
# this hook.
#
# It never stops the agent at the end of a turn (founder 2026-10-26: "build anyway under SEAM-215"). It used to ("block"
# with the reminder): Claude Code then told Claude that its answer had no visible output — though the person had seen it —
# and a chat repeated its whole answer; every stop also added a "Nothing new to save" reply.

input=$(cat)
data="$CLAUDE_PLUGIN_DATA"
session=$(printf '%s' "$input" | grep -o '"session_id"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
[ -z "$data" ] || [ -z "$session" ] && exit 0

# Saved this turn: nothing to remind, and the next turn starts clean.
if [ -f "$data/saved-$session" ]; then
  rm -f "$data/saved-$session" "$data/remind-$session"
  exit 0
fi
# No SeamTrail project for this folder: nothing to save into, so never remind.
[ -f "$data/project-$session" ] || exit 0
: > "$data/remind-$session" 2>/dev/null
exit 0
