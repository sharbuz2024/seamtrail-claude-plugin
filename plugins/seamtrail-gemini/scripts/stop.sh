#!/bin/sh
# SeamTrail · turn end (SEAM-253: the Claude Code plugin's stop.sh, for Gemini CLI's AfterAgent). Only in a chat with a
# SeamTrail project — the one its person picked, known at chat start (start.sh) or when they pick it (picked.sh): when
# nothing was saved to SeamTrail this turn (a note, or a change SeamTrail made — saved.sh), the agent is asked once to
# remember what was decided, learned or blocked — into that project, named — or to finish if nothing was. A chat saves
# only into its own project (SEAM-228), so a note about another project goes to the person, never into that project.
# No project: never asks. The words are the Claude Code plugin's.
# Gemini CLI: "block" rejects the turn's answer and sends the reason to the agent as the next prompt. The agent's answer
# to it may call tools and end in another turn-end check that no longer says stop_hook_active, so a marker keeps "never
# twice in one turn" (message.sh clears it at the person's next message). The agent saves; no chat text is sent
# anywhere by this hook.

. "$(dirname "$0")/common.sh"
[ -n "$session" ] || exit 0

# Saved this turn: finish, and start the next turn clean.
if [ -f "$data/saved-$session" ]; then
  rm -f "$data/saved-$session"
  exit 0
fi
# No SeamTrail project for this chat: nothing to save into, so never ask.
[ -f "$data/project-$session" ] || exit 0
# Asked once already this turn: never twice.
printf '%s' "$input" | grep -q '"stop_hook_active"[[:space:]]*:[[:space:]]*true' && exit 0
[ -f "$data/asked-$session" ] && exit 0

project=$(sed -n '1p' "$data/project-$session")
name=$(sed -n '2p' "$data/project-$session")
what="If in this turn your person decided something, learned a fact, hit or cleared a blocker, raised a risk, asked an open question or changed a status"
# SEAM-215 (founder 2026-10-23: "yes"): which kind a note is — the same words as SeamTrail's remember tool (KIND_GUIDE).
how="one note per thing (split a mixed sentence: an approval and a launch are two notes), each one plain sentence with kind and subject (the ticket key). decision = a choice a person made that could have gone another way (an approval too): who, what and because; never your own choice until your person agrees. status = where the work stands: built, merged, deployed, live, a ticket moved (your own build steps go here). fact = true whatever anyone chooses: how a tool works, a measured number, what the code or a doc says now. blocker = what stops the work now. risk = what may go wrong. question = open, for someone to answer"
done_="If none of that happened, finish now without saying anything more."
if [ "$project" = "ask" ]; then
  reason="SeamTrail: nothing was saved this turn. $what, call the SeamTrail remember tool now: $how. This folder belongs to more than one SeamTrail project: pass the projectId the conversation shows; if you cannot tell, leave it out and SeamTrail picks it, or answers with a short list to choose from. $done_"
else
  # A project picked during the chat (picked.sh) is known by its id only.
  label=""
  [ -n "$name" ] && label=" (the project “$name”)"
  reason="SeamTrail: nothing was saved this turn. $what, call the SeamTrail remember tool now with projectId $project$label: $how. This chat saves only into that project: if something belongs to another project, tell your person instead (they can switch this chat's project). $done_"
fi
: > "$data/asked-$session"
printf '{"decision":"block","reason":"%s"}\n' "$(printf '%s\n' "$reason" | json_text)"
exit 0
