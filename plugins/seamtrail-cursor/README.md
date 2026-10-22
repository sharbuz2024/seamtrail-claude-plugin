# SeamTrail for Cursor

One plugin that connects Cursor to SeamTrail, your team's shared memory of its projects. It works like the Claude Code plugin; the differences are listed below.

- **At chat start**, the plugin registers the chat with SeamTrail (its id and folder, as a Cursor chat) and gives the agent the chat's project context — or, before you pick, the question "Which SeamTrail project is this chat for?".
- **On every call the agent makes to SeamTrail's tools**, the plugin adds the chat's id and the ticket numbers in your last 3 messages and the agent's last 3 replies — numbers only, read on your computer — so SeamTrail knows which chat a note came from and brings it the news about its work. Only SeamTrail's tools are touched, and Cursor still asks you before tools run as it always does.
- **At turn end**, when nothing was saved to SeamTrail — no note, and no change SeamTrail made for you — the agent is asked once to remember what was decided, learned or blocked into the chat's project. Cursor sends this request as your next message, so you see it in the chat. It is never sent twice in a row, after you stop a turn, or while the agent is waiting for your answer. With "No project", or before you pick, it is never sent.

No conversation text is sent anywhere by the hooks. What they keep on your computer (the chat's project, ticket numbers, "saved this turn") is in `~/.local/state/seamtrail/cursor`.

## Install

1. Install the plugin, one of:
   - **Team marketplace** (Cursor Teams/Enterprise): an admin opens Dashboard → Plugins & MCPs → Add Marketplace → Import from Repo, with `https://github.com/sharbuz2024/seamtrail-claude-plugin`. Each person then installs SeamTrail from Customize.
   - **Cursor CLI**: `agent plugin marketplace add https://github.com/sharbuz2024/seamtrail-claude-plugin`, then install SeamTrail from `/plugin`.
   - **On your computer only**, one terminal command, then Developer: Reload Window in Cursor:

     ```
     d=$(mktemp -d) && git clone -q --depth 1 https://github.com/sharbuz2024/seamtrail-claude-plugin "$d" && mkdir -p ~/.cursor/plugins/local && rm -rf ~/.cursor/plugins/local/seamtrail-cursor && cp -R "$d/plugins/seamtrail-cursor" ~/.cursor/plugins/local/ && rm -rf "$d"
     ```

2. Sign in: in Customize → MCPs, connect the SeamTrail server and sign in to SeamTrail in the browser.
3. For the hooks, make a token in SeamTrail: **Settings → Agents · MCP connector → Token → Make a token**, named "Cursor plugin". It works as you; revoke it there any time. Add it to your shell profile (for example `~/.zshrc`), then quit and reopen Cursor:

   ```
   export SEAMTRAIL_TOKEN=paste-the-token-here
   ```

   Without the token, the SeamTrail tools still work, but chats are not registered and get no context at chat start.

If your company runs its own SeamTrail, also set `SEAMTRAIL_URL` to its address, and connect that address in Cursor instead of the plugin's server.

Cursor can also load Claude Code plugins (Cursor Settings → Agents → Third-Party Imports, on by default). If SeamTrail then shows twice in Customize, turn the Claude Code one off in Cursor.

## Not in Cursor

- **The news at every message you send.** Cursor's message hook cannot add anything to a message. SeamTrail's own tool replies still carry what changed.
- **Windows.** The hooks need `sh`. On Windows, the SeamTrail tools work and the hooks do nothing (WSL works).

Needs `sh`, `git` and `curl` (macOS and Linux have them). To add the chat id it also needs one of `jq`, `node` or `python3`; without them, calls go to SeamTrail without the chat id.
