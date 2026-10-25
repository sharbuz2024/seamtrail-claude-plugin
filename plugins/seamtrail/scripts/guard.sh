#!/bin/sh
# SeamTrail · guard (SEAM-230, SEAM-233). Just before Claude calls a SeamTrail tool — on this plugin's own SeamTrail
# server, or on a SeamTrail connection the person added themselves (Claude Code connects only one of them when both
# point at the same address, and the person's own wins), known by its server name — it adds this chat's id (Claude
# Code's session id) to the call, so SeamTrail knows which chat the call came from, and the ticket numbers in the chat's
# last few messages (tickets.sh), so SeamTrail can bring it the news that touches its work. It changes nothing else, never answers the
# permission question (Claude Code's own rules still decide), and never touches another server's tools. SeamTrail
# believes the id only for a chat this person registered (start.sh does that at chat start), and takes it out before the tool
# runs. With no JSON tool on this computer (jq, node or python3), the call simply goes on as it is.
#
# SEAM-233 (founder 2026-10-24: "the agent communication summary also make sure no secrets, credentials, security data"):
# Claude's workingOn line — what the person's latest message is about — is cleaned here, on this computer, before the
# call leaves: hint.js (node) or hint.py (python3) cut out secrets, credentials and security data with the same rules as
# the message (hint-rules.json). With only jq the line is left out; with no JSON tool at all the call goes as it is and
# SeamTrail cuts them out before keeping anything.
#
# SEAM-233 (founder 2026-10-25: "build the plugin side on a branch"): the id of the person's latest message (made by
# message.sh, waiting in turn-<chat>.json) goes with the call too, as messageId, so a note saved or a change made is
# tied to that message. SeamTrail takes it out before the tool runs, like the chat id.

input=$(cat)
prefix='mcp__plugin_seamtrail_seamtrail__'
# SEAM-233: the ticket numbers tickets.sh keeps on this computer (numbers only) go with the call as chatTickets.
session=$(printf '%s' "$input" | grep -o '"session_id"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
here=$(dirname "$0")
numbers=""
if [ -n "$CLAUDE_PLUGIN_DATA" ] && [ -n "$session" ] && [ -s "$CLAUDE_PLUGIN_DATA/tickets-$session.jsonl" ]; then
  numbers="$CLAUDE_PLUGIN_DATA/tickets-$session.jsonl"
fi
# SEAM-233: the latest message's id, from message.sh.
turn=""
if [ -n "$CLAUDE_PLUGIN_DATA" ] && [ -n "$session" ] && [ -s "$CLAUDE_PLUGIN_DATA/turn-$session.json" ]; then
  turn="$CLAUDE_PLUGIN_DATA/turn-$session.json"
fi

# node: wherever Claude Code was installed with npm.
if command -v node >/dev/null 2>&1; then
  printf '%s' "$input" | node -e '
    let s = ""; const [p, file, dir, turn] = process.argv.slice(1);
    process.stdin.on("data", (d) => (s += d)).on("end", () => {
      try {
        const d = JSON.parse(s);
        const server = String((d.mcp_server && d.mcp_server.name) || "").toLowerCase();
        if (!d.session_id || !(String(d.tool_name || "").startsWith(p) || server.includes("seamtrail"))) return;
        const updatedInput = Object.assign({}, d.tool_input || {}, { chatId: d.session_id });
        if (file) {
          try {
            const keys = new Set();
            for (const l of require("fs").readFileSync(file, "utf8").split("\n").filter(Boolean))
              for (const k of JSON.parse(l).k || []) keys.add(k);
            if (keys.size) updatedInput.chatTickets = [...keys].sort().join(",");
          } catch (e) {}
        }
        // SEAM-233: the workingOn line, cleaned by hint.js before it leaves; if that fails, it does not leave.
        if (typeof updatedInput.workingOn === "string") {
          try {
            const out = require("child_process").execFileSync(process.execPath, [dir + "/hint.js", dir + "/hint-rules.json"],
              { input: JSON.stringify({ session_id: "line", prompt: updatedInput.workingOn }), timeout: 3000 });
            const h = JSON.parse(String(out)).hint;
            if (h) updatedInput.workingOn = h; else delete updatedInput.workingOn;
          } catch (e) { delete updatedInput.workingOn; }
        }
        // SEAM-233: the latest message id, so what this call saves is tied to that message.
        if (turn) {
          try {
            const m = String(JSON.parse(require("fs").readFileSync(turn, "utf8")).messageId || "");
            if (/^[A-Za-z0-9_-]{8,100}$/.test(m)) updatedInput.messageId = m;
          } catch (e) {}
        }
        process.stdout.write(JSON.stringify({ hookSpecificOutput: { hookEventName: "PreToolUse", updatedInput } }));
      } catch (e) {}
    });' "$prefix" "$numbers" "$here" "$turn" 2>/dev/null
  exit 0
fi

# python3 — but not macOS's stand-in without the developer tools, which would open an install window.
py=$(command -v python3 2>/dev/null)
if [ -n "$py" ] && ! { [ "$(uname)" = Darwin ] && [ "$py" = /usr/bin/python3 ] && ! xcode-select -p >/dev/null 2>&1; }; then
  printf '%s' "$input" | "$py" -c '
import json, re, sys
p = sys.argv[1]
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
server = str((d.get("mcp_server") or {}).get("name") or "").lower()
if d.get("session_id") and (str(d.get("tool_name") or "").startswith(p) or "seamtrail" in server):
    i = dict(d.get("tool_input") or {})
    i["chatId"] = d["session_id"]
    if len(sys.argv) > 2 and sys.argv[2]:
        try:
            with open(sys.argv[2]) as f:
                keys = sorted({k for l in f if l.strip() for k in json.loads(l).get("k", [])})
            if keys:
                i["chatTickets"] = ",".join(keys)
        except Exception:
            pass
    # SEAM-233: the workingOn line, cleaned by hint.py before it leaves; if that fails, it does not leave.
    if isinstance(i.get("workingOn"), str):
        try:
            import subprocess
            here = sys.argv[3]
            out = subprocess.run([sys.executable, "-I", here + "/hint.py", here + "/hint-rules.json"],
                                 input=json.dumps({"session_id": "line", "prompt": i["workingOn"]}),
                                 capture_output=True, text=True, timeout=3).stdout
            h = json.loads(out).get("hint")
            if h:
                i["workingOn"] = h
            else:
                del i["workingOn"]
        except Exception:
            i.pop("workingOn", None)
    # SEAM-233: the latest message id, so what this call saves is tied to that message.
    if len(sys.argv) > 4 and sys.argv[4]:
        try:
            with open(sys.argv[4]) as f:
                m = str(json.load(f).get("messageId") or "")
            if re.fullmatch(r"[A-Za-z0-9_-]{8,100}", m):
                i["messageId"] = m
        except Exception:
            pass
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse", "updatedInput": i}}))
' "$prefix" "$numbers" "$here" "$turn" 2>/dev/null
  exit 0
fi
# jq (on macOS 15 and later, and most Linux machines), when there is no node or python3 to clean Claude's line: the
# line is left out (SEAM-233).
if command -v jq >/dev/null 2>&1; then
  if [ -n "$numbers" ]; then set -- --slurpfile seen "$numbers"; else set -- --argjson seen '[]'; fi
  # SEAM-233: the latest message id, from a turn file jq can read (a broken one is left out, never the call).
  if [ -n "$turn" ] && jq -e . "$turn" >/dev/null 2>&1; then set -- "$@" --slurpfile turn "$turn"; else set -- "$@" --argjson turn '[]'; fi
  printf '%s' "$input" | jq -c --arg p "$prefix" "$@" '
    select((.session_id // "") != ""
      and (((.tool_name // "") | startswith($p))
        or ((.mcp_server.name // "") | ascii_downcase | contains("seamtrail"))))
    | ($seen | map(.k // []) | add // [] | unique | join(",")) as $keys
    | (($turn[0].messageId? // "") | tostring) as $mid
    | {hookSpecificOutput: {hookEventName: "PreToolUse",
        updatedInput: ((.tool_input // {} | del(.workingOn)) + {chatId: .session_id}
          + (if $keys != "" then {chatTickets: $keys} else {} end)
          + (if ($mid | test("^[A-Za-z0-9_-]{8,100}$")) then {messageId: $mid} else {} end))}}' 2>/dev/null
  exit 0
fi

exit 0
