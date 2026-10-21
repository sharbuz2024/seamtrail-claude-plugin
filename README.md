# SeamTrail for Claude Code

One plugin that connects Claude Code to SeamTrail, your team's shared memory of its projects.

- **At chat start**, Claude Code gets the project this folder works on (matched from its git remote and the ticket in the branch name): where it stands, decisions with reasons, drift, and your own tickets and news.
- **At each message**, the plugin registers this chat with SeamTrail: its id, its name (when you gave it one) and its folder. The name is shown only to you.
- **On every call Claude makes to SeamTrail's tools**, the plugin adds this chat's id, so SeamTrail knows which chat a note or question came from. SeamTrail believes the id only for a chat you registered; any other id is ignored. The plugin touches only this plugin's own SeamTrail tools, and never answers a permission question for you.
- **At turn end**, when nothing was saved to SeamTrail, Claude is asked once to remember what was decided, learned or blocked into that project (named, with its id), or to finish if nothing was. If the folder belongs to two projects, Claude asks you which first. If it belongs to none, Claude is never asked. Claude saves through SeamTrail's own tools; the hooks send no chat text anywhere.

## Install

1. In SeamTrail: **Settings → Agents · MCP connector → Make a token**. Name it "Claude Code plugin".
2. In Claude Code:

   ```
   /plugin marketplace add sharbuz2024/seamtrail-claude-plugin
   /plugin install seamtrail@seamtrail
   ```

3. Paste the token when Claude Code asks for it. It is kept in your computer's secure store.

If SeamTrail is already connected to Claude Code another way, remove that connection, or Claude sees every SeamTrail tool twice.

Needs `sh`, `git` and `curl` (macOS and Linux have them). To add the chat id it also needs one of `jq`, `node` or `python3`; without them, calls go to SeamTrail without the chat id, as before.
