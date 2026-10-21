#!/bin/sh
# SeamTrail · guard (SEAM-230). Just before Claude calls a SeamTrail tool — on this plugin's own SeamTrail server, or
# on a SeamTrail connection the person added themselves (Claude Code connects only one of them when both point at the
# same address, and the person's own wins), known by its server name — it adds this chat's id (Claude Code's session
# id) to the call, so SeamTrail knows which chat the call came from. It changes nothing else, never answers the
# permission question (Claude Code's own rules still decide), and never touches another server's tools. SeamTrail
# believes the id only for a chat this person registered (start.sh does that at chat start), and takes it out before the tool
# runs. With no JSON tool on this computer (jq, node or python3), the call simply goes on as it is.

input=$(cat)
prefix='mcp__plugin_seamtrail_seamtrail__'

# jq: on macOS 15 and later, and on most Linux machines.
if command -v jq >/dev/null 2>&1; then
  printf '%s' "$input" | jq -c --arg p "$prefix" '
    select((.session_id // "") != ""
      and (((.tool_name // "") | startswith($p))
        or ((.mcp_server.name // "") | ascii_downcase | contains("seamtrail"))))
    | {hookSpecificOutput: {hookEventName: "PreToolUse",
        updatedInput: ((.tool_input // {}) + {chatId: .session_id})}}' 2>/dev/null
  exit 0
fi

# node: wherever Claude Code was installed with npm.
if command -v node >/dev/null 2>&1; then
  printf '%s' "$input" | node -e '
    let s = ""; const p = process.argv[1];
    process.stdin.on("data", (d) => (s += d)).on("end", () => {
      try {
        const d = JSON.parse(s);
        const server = String((d.mcp_server && d.mcp_server.name) || "").toLowerCase();
        if (!d.session_id || !(String(d.tool_name || "").startsWith(p) || server.includes("seamtrail"))) return;
        const updatedInput = Object.assign({}, d.tool_input || {}, { chatId: d.session_id });
        process.stdout.write(JSON.stringify({ hookSpecificOutput: { hookEventName: "PreToolUse", updatedInput } }));
      } catch (e) {}
    });' "$prefix" 2>/dev/null
  exit 0
fi

# python3 — but not macOS's stand-in without the developer tools, which would open an install window.
py=$(command -v python3 2>/dev/null)
if [ -n "$py" ]; then
  if [ "$(uname)" = Darwin ] && [ "$py" = /usr/bin/python3 ] && ! xcode-select -p >/dev/null 2>&1; then exit 0; fi
  printf '%s' "$input" | "$py" -c '
import json, sys
p = sys.argv[1]
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
server = str((d.get("mcp_server") or {}).get("name") or "").lower()
if d.get("session_id") and (str(d.get("tool_name") or "").startswith(p) or "seamtrail" in server):
    i = dict(d.get("tool_input") or {})
    i["chatId"] = d["session_id"]
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse", "updatedInput": i}}))
' "$prefix" 2>/dev/null
fi
exit 0
