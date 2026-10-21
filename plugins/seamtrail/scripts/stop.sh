#!/bin/sh
# SeamTrail · turn end (SEAM-215). Only in a folder SeamTrail matched to a project at chat start (start.sh): when
# nothing was saved to SeamTrail this turn, the agent is asked once to remember what was decided, learned or
# blocked — into that project, named — or to finish if nothing was. Two projects matched: it asks which first.
# No project: never asks. The agent saves; no chat text is sent anywhere by this hook.

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
  reason="SeamTrail: nothing was saved this turn. $what, ask your person which SeamTrail project it belongs to (this folder belongs to more than one; never guess), then call the SeamTrail remember tool with that projectId: $how. $done_"
else
  reason="SeamTrail: nothing was saved this turn. $what, call the SeamTrail remember tool now with projectId $project (the project “$name”): $how. If it is about another project, ask your person which one first; never guess. $done_"
fi
printf '{"decision":"block","reason":"%s"}\n' "$reason"
exit 0
