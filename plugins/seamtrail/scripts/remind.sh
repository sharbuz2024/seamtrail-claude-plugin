#!/bin/sh
# SeamTrail · the save reminder, with the person's next message (SEAM-215; founder 2026-10-26: "build anyway under
# SEAM-215"). When the last turn of a chat with a SeamTrail project saved nothing (stop.sh noted it on this computer),
# the agent is asked once, beside the person's new message, to remember what that turn decided, learned or blocked —
# into that project, named — and otherwise to say nothing about it. A chat saves only into its own project (SEAM-228),
# so a note about another project goes to the person, never into that project. Two projects matched (an older
# SeamTrail): the agent tells from the conversation, or leaves the project out and SeamTrail picks it or asks back
# (SEAM-219). A note older than about a day is dropped. No chat text is sent anywhere by this hook.

input=$(cat)
data="$CLAUDE_PLUGIN_DATA"
session=$(printf '%s' "$input" | grep -o '"session_id"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
[ -z "$data" ] || [ -z "$session" ] && exit 0
find "$data" -name 'remind-*' -mtime +1 -exec rm -f {} + 2>/dev/null
[ -f "$data/remind-$session" ] || exit 0
rm -f "$data/remind-$session"
[ -f "$data/project-$session" ] || exit 0

project=$(sed -n '1p' "$data/project-$session")
name=$(sed -n '2p' "$data/project-$session")
what="If in your last turn your person decided something, learned a fact, hit or cleared a blocker, raised a risk, asked an open question or changed a status"
# SEAM-215 (founder 2026-10-23: "yes"): which kind a note is — the same words as SeamTrail's remember tool (KIND_GUIDE).
how="one note per thing (split a mixed sentence: an approval and a launch are two notes), each one plain sentence with kind and subject (the ticket key). decision = a choice a person made that could have gone another way (an approval too): who, what and because; never your own choice until your person agrees. status = where the work stands: built, merged, deployed, live, a ticket moved (your own build steps go here). fact = true whatever anyone chooses: how a tool works, a measured number, what the code or a doc says now. blocker = what stops the work now. risk = what may go wrong. question = open, for someone to answer"
quiet="Your last answer was shown to your person: never repeat it. If none of that happened, do not mention this reminder; just answer the new message."
if [ "$project" = "ask" ]; then
  printf '%s\n' "SeamTrail: nothing was saved in your last turn. $what, call the SeamTrail remember tool now: $how. This folder belongs to more than one SeamTrail project: pass the projectId the conversation shows; if you cannot tell, leave it out and SeamTrail picks it, or answers with a short list to choose from. $quiet"
else
  # A project picked during the chat (picked.sh) is known by its id only.
  label=""
  [ -n "$name" ] && label=" (the project “$name”)"
  printf '%s\n' "SeamTrail: nothing was saved in your last turn. $what, call the SeamTrail remember tool now with projectId $project$label: $how. This chat saves only into that project: if something belongs to another project, tell your person instead (they can switch this chat's project). $quiet"
fi
exit 0
