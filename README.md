# SeamTrail for Claude Code

One plugin that connects Claude Code to SeamTrail, your team's shared memory of its projects.

- **At chat start**, the plugin registers this chat with SeamTrail: its id, its name (when you gave it one) and its folder. The name is shown only to you.
- **At your first message in a new chat**, Claude asks you once: "Which SeamTrail project is this chat for?" — three of your projects (the folder's repository's project first, then the ones you used last), "No project" (saved only in your private memory), or type another. SeamTrail keeps your answer for this chat: reopen the chat and it is not asked again; after /clear, a chat with a name keeps its project.
- **From then on**, Claude Code gets that project's context at chat start (where it stands, decisions with reasons, drift, your own tickets and news), and SeamTrail saves only into that project from this chat. Claude can still read other projects when you ask. To move the chat to another project, Claude asks you "Set project X for this chat from now on?" and switches only on your yes. Until you pick, SeamTrail reads but saves nothing from the chat.
- **On every call Claude makes to SeamTrail's tools**, the plugin adds this chat's id, so SeamTrail knows which chat a note or question came from. SeamTrail believes the id only for a chat you registered; any other id is ignored. It tags only SeamTrail's tools — this plugin's, or a SeamTrail connection you added yourself (Claude Code connects just one when both point at the same address) — and never answers a permission question for you.
- **The news that touches this chat's work.** Each of your chats gets each piece of the project's news once (not only the first chat to look). News about a ticket goes to the chats working on that ticket — named in the chat, in its branch, read through SeamTrail or in its own notes — and news about the whole project to every chat. Each line says who already saw it ("you saw this in “UI fixes”", "also seen by Priya"); other people's chat names are never shown.
- **What the chat works on — never the conversation.** With its SeamTrail calls, Claude adds a short summary of its own (2 to 5 sentences) of the work going on in the chat and what is being discussed, without names or secrets, and never writes it in the chat; the plugin adds the ticket numbers in your last 3 messages and Claude's last 3 replies — numbers only, read on your computer. SeamTrail uses them only to find the news for the chat (with the chat's own notes and the tickets it read): they are never shown to anyone, never saved as a note, and deleted about a day after they arrive.
- **At every message you send**, SeamTrail hands Claude, with your message, what is new on the chat's work since it last looked, and the latest memory about the tickets your message names — only what is still true (a replaced decision is not handed over), and only what the chat was not given yet. Only the chat id and those ticket numbers go to SeamTrail, never your words. When there is nothing to tell, nothing is added.
- **At turn end**, when nothing was saved to SeamTrail — no note, and no change SeamTrail made for you, such as a ticket moved or created (SeamTrail records those itself) — Claude is asked once to remember what was decided, learned or blocked into the chat's project (named, with its id), or to finish if nothing was. Something about another project is never saved from this chat: Claude tells you instead, and you can switch the chat's project. The reminder also says which kind each note is — one note per thing; a **decision** is a choice a person made (an approval too), with who and why, never Claude's own choice until you agree; Claude's build steps are a **status**; a **fact** is true whatever anyone chooses; plus **blocker**, **risk** and **question** — the same words as SeamTrail's own remember tool. With "No project", or before you pick, Claude is never asked. Claude saves through SeamTrail's own tools; the hooks send no conversation text.
- **When a newer plugin is out**, the chat-start hook has told SeamTrail this plugin's version, and Claude tells you once in that chat how to update. Settings → Agents · MCP connector → Plugins → Claude Code shows the same steps, with a button that copies them.

## Install

1. In SeamTrail: **Settings → Agents · MCP connector → Plugins → Claude Code** and follow the steps there. The token comes from **Token → Make a token**; name it "Claude Code plugin".
2. In a terminal, inside your repository's folder, so the whole team gets it:

   ```
   claude plugin marketplace add sharbuz2024/seamtrail-claude-plugin
   claude plugin install seamtrail@seamtrail --scope project
   ```

   This turns the plugin on for the repository in `.claude/settings.json`: commit that file, and each teammate runs the same install command once. For yourself only, leave out `--scope project`.

3. Paste the token when Claude Code asks for it. It is kept in your computer's secure store.

## Update

Claude Code does not update a plugin from someone else's marketplace by itself unless you turn that on. In a terminal, in your repository's folder:

```
claude plugin marketplace update seamtrail
claude plugin update seamtrail@seamtrail
```

Then type `/reload-plugins` in the chat, or start a new chat. To get updates by themselves: in Claude Code, type `/plugin`, open Marketplaces, pick seamtrail and choose Enable auto-update.

The newest version of each SeamTrail plugin, and how to update it, is in [updates.json](updates.json); SeamTrail reads it from here. A release bumps the plugin's version and its entry there together (`tests/updates.sh` checks).

If SeamTrail is already connected to Claude Code another way, remove that connection, or Claude sees every SeamTrail tool twice.

Needs `sh`, `git` and `curl` (macOS and Linux have them). To add the chat id it also needs one of `jq`, `node` or `python3`; without them, calls go to SeamTrail without the chat id, as before.
