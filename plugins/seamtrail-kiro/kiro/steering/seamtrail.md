---
inclusion: always
---

# SeamTrail plugin for Kiro

This workspace has SeamTrail's plugin for Kiro. SeamTrail is the team's shared memory of its projects: decisions and why, drift, blockers, tickets. Its hooks register each chat with SeamTrail when it starts, hand you what is new on the chat's work with each message, and, when nothing was saved to SeamTrail in a turn, ask you once at the turn's end to remember what was decided. Follow the SeamTrail server's own instructions and tool descriptions.

At chat start a SeamTrail hook tells you this chat's SeamTrail chat id ("This chat's SeamTrail chat id is …"). Kiro's hooks cannot add it to SeamTrail's tool calls the way SeamTrail's plugins for other assistants do, so you add it. On every call to a SeamTrail tool (a tool of the SeamTrail MCP server), add these arguments:

- chatId: that chat id, exactly as given. Without it SeamTrail cannot tell which chat a call comes from, and set_chat_project refuses.
- chatTickets: the ticket keys (like PAY-4) named in your person's last 3 messages and your last 3 replies, comma-separated. Keys only, never other text; leave it out when there are none.
- workingOn: 2 to 5 sentences of your own about the work going on in this chat and what is being discussed now, without names or secrets.

SeamTrail takes these out before the tool runs and uses them only to bring this chat its news. Never write the chat id or the workingOn summary in your replies. When no chat id was given in this chat (the hook did not run, or this computer has no SeamTrail token set), leave chatId out and pass the projectId on each call yourself.
