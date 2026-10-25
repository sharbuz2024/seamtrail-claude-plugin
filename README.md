# SeamTrail for Claude Code

One plugin that connects Claude Code to SeamTrail, your team's shared memory of its projects.

- **At chat start**, the plugin registers this chat with SeamTrail: its id, its name (when you gave it one) and its folder. The name is shown only to you.
- **At your first message in a new chat**, Claude asks you once: "Which SeamTrail project is this chat for?" — three of your projects (the folder's repository's project first, then the ones you used last), "No project" (saved only in your private memory), or type another. SeamTrail keeps your answer for this chat: reopen the chat and it is not asked again; after /clear, a chat with a name keeps its project.
- **From then on**, Claude Code gets that project's context at chat start (where it stands, decisions with reasons, drift, your own tickets and news), and SeamTrail saves only into that project from this chat. Claude can still read other projects when you ask. To move the chat to another project, Claude asks you "Set project X for this chat from now on?" and switches only on your yes. Until you pick, SeamTrail reads but saves nothing from the chat.
- **On every call Claude makes to SeamTrail's tools**, the plugin adds this chat's id, so SeamTrail knows which chat a note or question came from. SeamTrail believes the id only for a chat you registered; any other id is ignored. It tags only SeamTrail's tools — this plugin's, or a SeamTrail connection you added yourself (Claude Code connects just one when both point at the same address) — and never answers a permission question for you.
- **The news that touches this chat's work.** Each of your chats gets each piece of the project's news once (not only the first chat to look). News about a ticket goes to the chats working on that ticket — named in the chat, in its branch, read through SeamTrail or in its own notes — and news about the whole project to every chat. Each line says who already saw it ("you saw this in “UI fixes”", "also seen by Priya"); other people's chat names are never shown.
- **What Claude did for your latest message — never the conversation.** With its SeamTrail calls, Claude adds one or two sentences of its own on what you asked in your latest message and what it did, with no names and no secrets, credentials or security data, and never writes it in the chat. The plugin cleans that line on your computer before the call leaves, with the same rules as your messages (by `node` or `python3`; with only `jq` the line is left out), and SeamTrail cleans it again. The plugin also adds the ticket numbers in your last 3 messages and Claude's last 3 replies — numbers only, read on your computer. SeamTrail uses them only to find the news for the chat (with the chat's own notes and the tickets it read): they are never shown to anyone, never saved as a note, and deleted about a day after they arrive.
- **At every message you send**, SeamTrail hands Claude, with your message, what is new on the chat's work since it last looked, the latest memory about the tickets your message names, and what the message itself seems to be about — the ticket, document and notes its words point to, found by meaning — only what is still true (a replaced decision is not handed over), and only what the chat was not given yet. When there is nothing to tell, nothing is added.
- **What leaves your computer with a message:** the chat id, a new id for the message, the ticket numbers, and a search hint cut from that one message on your computer first — code blocks, secrets and credentials taken out (keys, tokens, passwords, links with a password, card numbers, long random strings), then the message itself when short, else its first 300 and last 200 characters and its links. It goes in the request body, never in the address; SeamTrail checks it for secrets again and uses it for that search. To make the search numbers SeamTrail sends it to OpenAI, which does not train on it and may keep it up to 30 days for abuse checks. Cleaning needs `node` or `python3`; without either, no words of your message are sent, only the chat id, the message's id and the ticket numbers.
- **At the end of each message**, once Claude has answered, the plugin sends a cut of what you asked and of Claude's final reply, both cleaned on your computer the same way, with the chat id, the message's id and the ticket numbers the two name. Every SeamTrail call Claude made for that message carried the same id, so the notes saved and the changes made are tied to it. SeamTrail cleans the cuts again and keeps them as this chat's history, by project, until your organization sets a delete time; only you can ask about your own. It makes their search numbers the same way (OpenAI, as above). It is sent once per message, in the background, so the chat never waits; when a turn-end reminder makes Claude go on, that second answer is not sent; without `node` or `python3`, nothing is sent.
- **At turn end**, when nothing was saved to SeamTrail — no note, and no change SeamTrail made for you, such as a ticket moved or created (SeamTrail records those itself) — Claude is asked once to remember what was decided, learned or blocked into the chat's project (named, with its id), or to finish if nothing was. Something about another project is never saved from this chat: Claude tells you instead, and you can switch the chat's project. The reminder also says which kind each note is — one note per thing; a **decision** is a choice a person made (an approval too), with who and why, never Claude's own choice until you agree; Claude's build steps are a **status**; a **fact** is true whatever anyone chooses; plus **blocker**, **risk** and **question** — the same words as SeamTrail's own remember tool. With "No project", or before you pick, Claude is never asked. Claude saves through SeamTrail's own tools; apart from the cleaned hint and cuts above, the hooks send no conversation text.
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
