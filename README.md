# SeamTrail for Claude Code

One plugin that connects Claude Code to SeamTrail, your team's shared memory of its projects.

- **At chat start**, the plugin registers this chat with SeamTrail: its id, its name (when you gave it one) and its folder. The name is shown only to you.
- **At your first message in a new chat**, Claude asks you once: "Which SeamTrail project is this chat for?" — three of your projects (the folder's repository's project first, then the ones you used last), "No project" (saved only in your private memory), or type another. SeamTrail keeps your answer for this chat: reopen the chat and it is not asked again; after /clear, a chat with a name keeps its project.
- **From then on**, Claude Code gets that project's context at chat start (where it stands, decisions with reasons, drift, your own tickets and news), and SeamTrail saves only into that project from this chat. Claude can still read other projects when you ask. To move the chat to another project, Claude asks you "Set project X for this chat from now on?" and switches only on your yes. Until you pick, SeamTrail reads but saves nothing from the chat.
- **On every call Claude makes to SeamTrail's tools**, the plugin adds this chat's id, so SeamTrail knows which chat a note or question came from. SeamTrail believes the id only for a chat you registered; any other id is ignored. It tags only SeamTrail's tools — this plugin's, or a SeamTrail connection you added yourself (Claude Code connects just one when both point at the same address) — and never answers a permission question for you.
- **The news that touches this chat's work.** Each of your chats gets each piece of the project's news once (not only the first chat to look). News about a ticket goes to the chats working on that ticket — named in the chat, in its branch, read through SeamTrail or in its own notes — and news about the whole project to every chat. Each line says who already saw it ("you saw this in “UI fixes”", "also seen by Priya"); other people's chat names are never shown.
- **What the chat works on — never the conversation.** With its SeamTrail calls, Claude adds a short summary of its own (2 to 5 sentences) of the work going on in the chat and what is being discussed, without names or secrets, and never writes it in the chat; the plugin adds the ticket numbers in your last 3 messages and Claude's last 3 replies — numbers only, read on your computer. SeamTrail uses them only to find the news for the chat (with the chat's own notes, the tickets it read and its questions to SeamTrail): they are never shown to anyone, never saved as a note, and deleted about a day after they arrive. Turn this off with the plugin's "Share what each chat works on" option.
- **At every message you send**, SeamTrail hands Claude, with your message, what is new on the chat's work since it last looked, and the latest memory about the tickets your message names — only what is still true (a replaced decision is not handed over), and only what the chat was not given yet. Only the chat id and those ticket numbers go to SeamTrail, never your words. When there is nothing to tell, nothing is added.
- **At turn end**, when nothing was saved to SeamTrail, Claude is asked once to remember what was decided, learned or blocked into the chat's project (named, with its id), or to finish if nothing was. With "No project", or before you pick, Claude is never asked. Claude saves through SeamTrail's own tools; the hooks send no conversation text.

## Install

1. In SeamTrail: **Settings → AI assistants → A tool that cannot sign in? → Make a token**. Name it "Claude Code plugin".
2. In Claude Code:

   ```
   /plugin marketplace add sharbuz2024/seamtrail-claude-plugin
   /plugin install seamtrail@seamtrail
   ```

3. Paste the token when Claude Code asks for it. It is kept in your computer's secure store.

If SeamTrail is already connected to Claude Code another way, remove that connection, or Claude sees every SeamTrail tool twice.

Needs `sh`, `git` and `curl` (macOS and Linux have them). To add the chat id it also needs one of `jq`, `node` or `python3`; without them, calls go to SeamTrail without the chat id, as before.
