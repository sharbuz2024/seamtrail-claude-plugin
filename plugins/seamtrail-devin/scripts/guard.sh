#!/bin/sh
# SeamTrail · guard, in the Devin CLI (SEAM-254: the Claude Code plugin's guard.sh — SEAM-230, SEAM-233 — in Devin's
# hook format). Just before Devin calls a SeamTrail tool — on this plugin's own SeamTrail server, or on a SeamTrail
# server the person added themselves, known by the server name in the tool's name (Devin names MCP tools
# mcp__<server>__<tool>) — it adds this chat's id (Devin's session id) to the call, so SeamTrail knows which chat the
# call came from, and the ticket numbers in the chat's last few messages (tickets.sh), so SeamTrail can bring it the
# news that touches its work. Devin merges hookSpecificOutput.updatedInput into the tool's arguments. It changes nothing
# else, never answers the permission question (Devin's own rules still decide), and never touches another server's
# tools. SeamTrail believes the id only for a chat this person registered (start.sh does that at chat start), and takes
# it out before the tool runs. With no JSON tool on this computer (jq, node or python3), the call simply goes on as it is.

. "$(dirname "$0")/lib.sh"
input=$(cat)
# SEAM-233: the ticket numbers tickets.sh keeps on this computer (numbers only) go with the call as chatTickets.
session=$(printf '%s' "$input" | grep -o '"session_id"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
numbers=""
if [ -n "$session" ] && [ -s "$data/tickets-$session.jsonl" ]; then
  numbers="$data/tickets-$session.jsonl"
fi

# jq: on macOS 15 and later, and on most Linux machines.
if command -v jq >/dev/null 2>&1; then
  if [ -n "$numbers" ]; then set -- --slurpfile seen "$numbers"; else set -- --argjson seen '[]'; fi
  printf '%s' "$input" | jq -c "$@" '
    ((.tool_name // "") | tostring) as $t
    | select((.session_id // "") != "" and ($t | startswith("mcp__"))
        and ($t | ltrimstr("mcp__") | split("__") | .[:-1] | join("__") | ascii_downcase | contains("seamtrail")))
    | ($seen | map(.k // []) | add // [] | unique | join(",")) as $keys
    | {hookSpecificOutput: {hookEventName: "PreToolUse",
        updatedInput: ((.tool_input // {}) + {chatId: .session_id}
          + (if $keys != "" then {chatTickets: $keys} else {} end))}}' 2>/dev/null
  exit 0
fi

# node: wherever it was installed with npm.
if command -v node >/dev/null 2>&1; then
  printf '%s' "$input" | node -e '
    let s = ""; const [file] = process.argv.slice(1);
    process.stdin.on("data", (d) => (s += d)).on("end", () => {
      try {
        const d = JSON.parse(s);
        const t = String(d.tool_name || "");
        const server = t.startsWith("mcp__") ? t.slice(5).split("__").slice(0, -1).join("__").toLowerCase() : "";
        if (!d.session_id || !server.includes("seamtrail")) return;
        const updatedInput = Object.assign({}, d.tool_input || {}, { chatId: d.session_id });
        if (file) {
          try {
            const keys = new Set();
            for (const l of require("fs").readFileSync(file, "utf8").split("\n").filter(Boolean))
              for (const k of JSON.parse(l).k || []) keys.add(k);
            if (keys.size) updatedInput.chatTickets = [...keys].sort().join(",");
          } catch (e) {}
        }
        process.stdout.write(JSON.stringify({ hookSpecificOutput: { hookEventName: "PreToolUse", updatedInput } }));
      } catch (e) {}
    });' "$numbers" 2>/dev/null
  exit 0
fi

# python3 — but not macOS's stand-in without the developer tools, which would open an install window.
py=$(command -v python3 2>/dev/null)
if [ -n "$py" ]; then
  if [ "$(uname)" = Darwin ] && [ "$py" = /usr/bin/python3 ] && ! xcode-select -p >/dev/null 2>&1; then exit 0; fi
  printf '%s' "$input" | "$py" -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
t = str(d.get("tool_name") or "")
server = "__".join(t[5:].split("__")[:-1]).lower() if t.startswith("mcp__") else ""
if d.get("session_id") and "seamtrail" in server:
    i = dict(d.get("tool_input") or {})
    i["chatId"] = d["session_id"]
    if len(sys.argv) > 1 and sys.argv[1]:
        try:
            with open(sys.argv[1]) as f:
                keys = sorted({k for l in f if l.strip() for k in json.loads(l).get("k", [])})
            if keys:
                i["chatTickets"] = ",".join(keys)
        except Exception:
            pass
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse", "updatedInput": i}}))
' "$numbers" 2>/dev/null
fi
exit 0
