# SeamTrail for Claude Code

One plugin that connects Claude Code to SeamTrail, your team's shared memory of its projects.

- **At chat start**, Claude Code gets the project this folder works on (matched from its git remote and the ticket in the branch name): where it stands, decisions with reasons, drift, and your own tickets and news.
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

Needs `sh`, `git` and `curl` (macOS and Linux have them).
