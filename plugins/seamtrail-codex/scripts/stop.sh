#!/bin/sh
# SeamTrail · turn end, in Codex (SEAM-252; the Claude Code plugin's stop.sh, SEAM-215, SEAM-228). Only in a chat with a
# SeamTrail project — the one its person picked, known at chat start (start.sh) or when they pick it (picked.sh); an
# older SeamTrail matched it from the folder: when nothing was saved to SeamTrail this turn (a note, or a change
# SeamTrail made — saved.sh), this notes it on this computer (remind-<chat>), and with the person's next message the
# agent is asked once to remember what this turn decided, learned or blocked (message.sh, remind.sh). No project: never
# reminds. No chat text is sent anywhere by this hook. Codex runs Stop only for the chat itself; a subagent's end is
# SubagentStop, which this plugin leaves alone.
#
# It never stops the agent at the end of a turn (founder 2026-10-26 for Claude Code; 2026-11-01: "yes do all six"):
# stopping it (a "block" here) added a reply the person did not ask for each time, and in Claude Code made a chat repeat
# its whole answer.

input=$(cat)
data="${PLUGIN_DATA:-${XDG_STATE_HOME:-$HOME/.local/state}/seamtrail/codex}"
session=$(printf '%s' "$input" | grep -o '"session_id"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
[ -z "$session" ] && exit 0

# Saved this turn: nothing to remind, and the next turn starts clean.
if [ -f "$data/saved-$session" ]; then
  rm -f "$data/saved-$session" "$data/remind-$session"
  exit 0
fi
# No SeamTrail project for this chat: nothing to save into, so never remind.
[ -f "$data/project-$session" ] || exit 0
: > "$data/remind-$session" 2>/dev/null
exit 0
