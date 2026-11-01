---
name: seamtrail
description: Use SeamTrail, the team's shared memory of its projects (decisions and why, drift, blockers, tickets), for any project work — before answering about a project, its tickets, documents, people or decisions, before planning or changing code, and before ending a turn in which something was decided, learned, blocked or changed.
---

# SeamTrail

SeamTrail (this plugin's "seamtrail" MCP server) is the team's shared memory of its projects: what was decided and why, what is blocked, what is out of date (drift), where the work stands. A live tool read beats it.

## At chat start

- If SeamTrail already gave this chat its project's context or a question to ask (a note that starts "SeamTrail is your team's shared memory"), work from it and do what it says.
- If not (its hooks are not trusted yet in /hooks, or SEAMTRAIL_TOKEN is not set for them): call list_projects, then project_context once for the project the work is on. Ask your person which project when you cannot tell.

## While you work

- Ask SeamTrail before you answer about a project, its tickets, documents, people or decisions, before you plan, and before you change code in its repository: project_context once per chat, then ticket_details, search_memory, get_chain or ask_seamtrail for more. Never guess to fill a gap.
- Changes to tickets or documents (create, move, comment, assign, describe): ask your person first, then tell ask_seamtrail in plain words with the projectId, and tell them the undo it returns.

## Before the turn ends

- If your person decided something, learned a fact, hit or cleared a blocker, raised a risk, asked an open question or changed a status: call remember with the chat's projectId, one note per thing (split a mixed sentence: an approval and a launch are two notes), each one plain sentence with kind and subject (the ticket key). Do not wait to be asked. Never store secrets.
- Which kind: decision = a choice a person made that could have gone another way (an approval too): who, what and because; never your own choice until your person agrees. status = where the work stands: built, merged, deployed, live, a ticket moved (your own build steps go here). fact = true whatever anyone chooses: how a tool works, a measured number, what the code or a doc says now. blocker = what stops the work now. risk = what may go wrong. question = open, for someone to answer.
- When SeamTrail's save reminder comes with a message, follow it once; if none of that happened, do not mention it. Never repeat your last answer because of it.
- Before you resolve or replace someone's decision, tell your person what was decided, by whom and when. If remember returns a question, ask them, and call settle_question only on their yes.
