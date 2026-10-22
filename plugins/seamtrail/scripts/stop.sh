#!/bin/sh
# SeamTrail · turn end (SEAM-215, SEAM-228). Only in a chat with a SeamTrail project — the one its person picked, known
# at chat start (start.sh) or when they pick it (picked.sh); an older SeamTrail matched it from the folder: when
# nothing was saved to SeamTrail this turn (a note, or a change SeamTrail made — saved.sh), the agent is asked once to
# remember what was decided, learned or blocked — into that project, named — or to finish if nothing was. A chat
# saves only into its own project (SEAM-228), so a note about another project goes to the person, never into that
# project. Two projects matched (an older SeamTrail): the agent tells from the conversation, or leaves the project out
# and SeamTrail picks it or asks back (SEAM-219). No project: never asks. The agent saves; no chat text is sent
# anywhere by this hook.

input=$(cat)
data="$CLAUDE_PLUGIN_DATA"
session=$(printf '%s' "$input" | grep -o '"session_id"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
[ -z "$data" ] || [ -z "$session" ] && exit 0

# Saved this turn: finish, and start the next turn clean.
if [ -f "$data/saved-$session" ]; then
  rm -f "$data/saved-$session"
  exit 0
fi
# No SeamTrail project for this folder: nothing to save into, so never ask.
[ -f "$data/project-$session" ] || exit 0
# Asked once already this turn: never twice.
printf '%s' "$input" | grep -q '"stop_hook_active"[[:space:]]*:[[:space:]]*true' && exit 0

project=$(sed -n '1p' "$data/project-$session")
name=$(sed -n '2p' "$data/project-$session")
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
printf '{"decision":"block","reason":"%s"}\n' "$reason"
exit 0
