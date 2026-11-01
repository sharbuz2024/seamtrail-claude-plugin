# SeamTrail for Kiro

Connects Kiro — the IDE (1.0 and later) and the Kiro CLI (V3) — to SeamTrail, your team's shared memory of its projects, with the same hooks as SeamTrail's Claude Code plugin, as far as Kiro's hooks allow.

- **At chat start**, the chat is registered with SeamTrail (its id and folder), and Kiro's agent gets the project's context — or, in a new chat, asks you once which SeamTrail project the chat is for.
- **At every message you send**, the agent gets what is new on the chat's work, the latest memory about the tickets your message names, and what the message itself seems to be about (found by meaning). What goes to SeamTrail: the chat id, those ticket numbers, and a search hint cut from that one message on your computer first — code blocks, secrets and credentials taken out — sent in the request body, used only for the search and not kept. Cleaning needs `node` or `python3`; without either, no words of your message are sent.
- **On every SeamTrail call**, the agent adds the chat's id, the ticket numbers of the last few messages and a short summary of the work. In Claude Code a hook adds these; a Kiro hook cannot change a tool call, so the steering file asks the agent to.
- **With your next message**, when nothing was saved to SeamTrail in the last turn, the agent is asked once to remember what that turn decided, learned or blocked into the chat's project, and otherwise says nothing about it. The plugin never stops the agent at the end of a turn.

## How it is built

Kiro's add-ons ("powers") carry an MCP server and skills but no hooks, and install for one person only. Kiro reads hooks, steering and MCP settings from the repository's `.kiro` folder, so SeamTrail for Kiro is four things there, committed with the code:

- `.kiro/settings/mcp.json` — the SeamTrail MCP server (you sign in once in the browser)
- `.kiro/hooks/seamtrail.json` — the hooks
- `.kiro/steering/seamtrail.md` — what the agent does for them, in every chat
- `.kiro/seamtrail/*.sh` — the hook scripts

## Install

1. In a terminal, inside your repository's folder:

   ```
   curl -fsSL https://raw.githubusercontent.com/sharbuz2024/seamtrail-claude-plugin/main/plugins/seamtrail-kiro/install.sh | sh
   ```

   Commit the files it lists: every teammate who opens the repository in Kiro gets SeamTrail. If `.kiro/settings/mcp.json` already lists servers, SeamTrail is added beside them. For yourself only, end the command with `sh -s -- --user` instead of `sh` (it writes `~/.kiro`). Run it again to update.

2. The hooks work as you with a SeamTrail token. In SeamTrail: **Settings → Agents · MCP connector → Token → Make a token**, name it "Kiro plugin". Add `export SEAMTRAIL_TOKEN=<your token>` to your shell profile (`~/.zshrc` or `~/.bashrc`), then quit and reopen Kiro. Each teammate does this once, with their own token.

3. Open the repository in Kiro, or run `kiro-cli` in it. Kiro opens a browser tab: sign in to SeamTrail and press Allow.

Needs `sh`, `git` and `curl` (macOS and Linux have them; on Windows, use WSL). Without the token, the hooks stay silent and SeamTrail works over MCP alone. If SeamTrail is also connected in `~/.kiro/settings/mcp.json` under another name, remove that one, or Kiro sees every SeamTrail tool twice.

With your own agent in the Kiro CLI: if it does not load the workspace's MCP servers or steering, set `"includeMcpJson": true` and add `"file://.kiro/steering/seamtrail.md"` to its `resources`.
