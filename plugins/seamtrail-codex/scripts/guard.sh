#!/bin/sh
# SeamTrail · guard, in Codex (SEAM-252; the Claude Code plugin's guard.sh, SEAM-230, SEAM-233). Just before Codex calls
# a SeamTrail tool — on this plugin's SeamTrail server or on a SeamTrail connection the person added themselves, known
# by its server name in the tool's name (mcp__<server>__<tool>, the server's name holding "seamtrail") — it adds this
# chat's id (Codex's session id; a subagent's calls carry its parent chat's id) to the call, so SeamTrail knows which
# chat the call came from, and the ticket numbers in the chat's last few messages (tickets.sh), so SeamTrail can bring
# it the news that touches its work. It changes nothing else and never touches another server's tools. Codex takes a
# changed call only with permissionDecision "allow"; that only lets the change through — Codex still asks the person
# before a SeamTrail call exactly as its own settings say (the approval is decided apart from this hook). SeamTrail
# believes the id only for a chat this person registered (start.sh does that at chat start), and takes it out before
# the tool runs. With no JSON tool on this computer (jq, node or python3), the call simply goes on as it is.

input=$(cat)
data="${PLUGIN_DATA:-${XDG_STATE_HOME:-$HOME/.local/state}/seamtrail/codex}"
# SEAM-233: the ticket numbers tickets.sh keeps on this computer (numbers only) go with the call as chatTickets.
session=$(printf '%s' "$input" | grep -o '"session_id"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
numbers=""
if [ -n "$session" ] && [ -s "$data/tickets-$session.jsonl" ]; then
  numbers="$data/tickets-$session.jsonl"
fi
# A SeamTrail server's tool: mcp__<a server whose name holds "seamtrail">__<tool>, in any case.
seamtrail='^mcp__.*seamtrail.*__.'

# jq: on macOS 15 and later, and on most Linux machines.
if command -v jq >/dev/null 2>&1; then
  if [ -n "$numbers" ]; then set -- --slurpfile seen "$numbers"; else set -- --argjson seen '[]'; fi
  printf '%s' "$input" | jq -c --arg p "$seamtrail" "$@" '
    select((.session_id // "") != ""
      and ((.tool_name // "") | ascii_downcase | test($p))
      and ((.tool_input // {}) | type) == "object")
    | ($seen | map(.k // []) | add // [] | unique | join(",")) as $keys
    | {hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "allow",
        updatedInput: ((.tool_input // {}) + {chatId: .session_id}
          + (if $keys != "" then {chatTickets: $keys} else {} end))}}' 2>/dev/null
  exit 0
fi

# node: wherever Codex was installed with npm.
if command -v node >/dev/null 2>&1; then
  printf '%s' "$input" | node -e '
    let s = ""; const [p, file] = process.argv.slice(1);
    process.stdin.on("data", (d) => (s += d)).on("end", () => {
      try {
        const d = JSON.parse(s);
        const ti = d.tool_input == null ? {} : d.tool_input;
        if (!d.session_id || !new RegExp(p).test(String(d.tool_name || "").toLowerCase())) return;
        if (typeof ti !== "object" || Array.isArray(ti)) return;
        const updatedInput = Object.assign({}, ti, { chatId: d.session_id });
        if (file) {
          try {
            const keys = new Set();
            for (const l of require("fs").readFileSync(file, "utf8").split("\n").filter(Boolean))
              for (const k of JSON.parse(l).k || []) keys.add(k);
            if (keys.size) updatedInput.chatTickets = [...keys].sort().join(",");
          } catch (e) {}
        }
        process.stdout.write(JSON.stringify({ hookSpecificOutput: { hookEventName: "PreToolUse", permissionDecision: "allow", updatedInput } }));
      } catch (e) {}
    });' "$seamtrail" "$numbers" 2>/dev/null
  exit 0
fi

# python3 — but not macOS's stand-in without the developer tools, which would open an install window.
py=$(command -v python3 2>/dev/null)
if [ -n "$py" ]; then
  if [ "$(uname)" = Darwin ] && [ "$py" = /usr/bin/python3 ] && ! xcode-select -p >/dev/null 2>&1; then exit 0; fi
  printf '%s' "$input" | "$py" -c '
import json, re, sys
p = sys.argv[1]
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
ti = d.get("tool_input")
if ti is None:
    ti = {}
if d.get("session_id") and re.search(p, str(d.get("tool_name") or "").lower()) and isinstance(ti, dict):
    i = dict(ti)
    i["chatId"] = d["session_id"]
    if len(sys.argv) > 2 and sys.argv[2]:
        try:
            with open(sys.argv[2]) as f:
                keys = sorted({k for l in f if l.strip() for k in json.loads(l).get("k", [])})
            if keys:
                i["chatTickets"] = ",".join(keys)
        except Exception:
            pass
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "allow", "updatedInput": i}}))
' "$seamtrail" "$numbers" 2>/dev/null
fi
exit 0
