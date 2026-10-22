#!/bin/sh
# SeamTrail · turn end (SEAM-215, SEAM-228) — for Cursor (SEAM-256), on stop. Only in a chat with a SeamTrail project —
# the one its person picked, known at chat start (start.sh) or when they pick it (picked.sh): when nothing was saved to
# SeamTrail this turn (a note, or a change SeamTrail made — saved.sh), the agent is asked once to remember what was
# decided, learned or blocked — into that project, named — or to finish if nothing was. The words are the Claude Code
# plugin's, unchanged. A chat saves only into its own project (SEAM-228), so a note about another project goes to the
# person, never into that project. No project: never asks. The agent saves; no chat text is sent anywhere by this hook.
#
# Cursor sends the reminder as the person's next message (followup_message), so it asks only at the end of a turn the
# person started (loop_count 0, and never right after its own reminder), that ended normally (status "completed"), and
# not while the agent waits for the person's answer (its last reply ended with a question, tickets.sh). Cursor runs
# this hook from the workspace folder; it reads and writes only this plugin's notes (lib.sh).

lib="$(dirname "$0")/lib.sh"
[ -f "$lib" ] || exit 0
. "$lib"

input=$(cat)
chat=$(st_chat "$input")
[ -n "$chat" ] || exit 0
dir="$st_state"

# The agent's last reply this turn ended with a question (the same turn, when both sides know its id).
asked=no
if [ -f "$dir/asked-$chat" ]; then
  was=$(cat "$dir/asked-$chat" 2>/dev/null)
  rm -f "$dir/asked-$chat"
  turn=$(st_field "$input" generation_id)
  if [ -z "$was" ] || [ -z "$turn" ] || [ "$was" = "$turn" ]; then asked=yes; fi
fi

# Saved this turn: finish, and start the next turn clean.
if [ -f "$dir/saved-$chat" ]; then
  rm -f "$dir/saved-$chat" "$dir/reminded-$chat"
  exit 0
fi
# This turn answered the reminder: never twice in a row.
if [ -f "$dir/reminded-$chat" ]; then
  rm -f "$dir/reminded-$chat"
  exit 0
fi
# No SeamTrail project for this chat: nothing to save into, so never ask.
[ -f "$dir/project-$chat" ] || exit 0
# Only at the end of a turn the person started, that ended normally, and not while the agent waits for an answer.
loop=$(printf '%s' "$input" | grep -o '"loop_count"[[:space:]]*:[[:space:]]*[0-9]*' | head -n 1 | sed 's/.*[^0-9]//')
case "$loop" in '' | 0) ;; *) exit 0 ;; esac
case "$(st_field "$input" status)" in '' | completed) ;; *) exit 0 ;; esac
[ "$asked" = yes ] && exit 0

project=$(sed -n '1p' "$dir/project-$chat")
name=$(sed -n '2p' "$dir/project-$chat")
case "$project" in '' | *[!A-Za-z0-9-]*) exit 0 ;; esac
# SeamTrail sends the name JSON-escaped (ASCII); a name that is not is left out rather than break the answer.
rest=$(printf '%s' "$name" | sed -E 's#\\(["\\/bfnrt]|u[0-9A-Fa-f]{4})##g')
case "$rest" in *\\* | *\"* | *[[:cntrl:]]*) name="" ;; esac

what="If in this turn your person decided something, learned a fact, hit or cleared a blocker, raised a risk, asked an open question or changed a status"
how="one plain sentence each, with kind and subject, a decision with its reason"
done_="If none of that happened, finish now without saying anything more."
if [ "$project" = "ask" ]; then
  reason="SeamTrail: nothing was saved this turn. $what, call the SeamTrail remember tool now: $how. This folder belongs to more than one SeamTrail project: pass the projectId the conversation shows; if you cannot tell, leave it out and SeamTrail picks it, or answers with a short list to choose from. $done_"
else
  # A project picked during the chat (picked.sh) is known by its id only.
  label=""
  [ -n "$name" ] && label=" (the project “$name”)"
  reason="SeamTrail: nothing was saved this turn. $what, call the SeamTrail remember tool now with projectId $project$label: $how. This chat saves only into that project: if something belongs to another project, tell your person instead (they can switch this chat's project). $done_"
fi
mkdir -p "$dir" 2>/dev/null && : > "$dir/reminded-$chat"
printf '{"followup_message":"%s"}\n' "$reason"
exit 0
