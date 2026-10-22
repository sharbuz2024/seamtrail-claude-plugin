#!/bin/sh
# SeamTrail · guard (SEAM-255; the Claude Code plugin's guard.sh — SEAM-230, SEAM-233 — for VS Code). Just before the
# agent calls one of SeamTrail's tools — known by its name, which holds the server's ("seamtrail"); VS Code drops a
# hook's matcher, so this runs before every tool and lets all others go untouched — it adds this chat's id (VS Code's
# session id) to the call, so SeamTrail knows which chat the call came from, and the ticket numbers in the person's
# last few messages (tickets.sh), so SeamTrail can bring the chat the news that touches its work. It changes nothing
# else and never answers the permission question (VS Code's own rules still decide). SeamTrail believes the id only for
# a chat this person registered (start.sh does that at chat start), and takes it out before the tool runs. The
# Copilot harness may hand the arguments over as a JSON string; they go back as an object. With no JSON tool on this
# computer (jq, node or python3), or arguments it cannot read, the call simply goes on as it is.

input=$(cat)
# Most calls are to other tools: done at once (no process started) unless the input names SeamTrail anywhere.
case "$input" in *[Ss][Ee][Aa][Mm][Tt][Rr][Aa][Ii][Ll]*) ;; *) exit 0 ;; esac
. "$(dirname "$0")/lib.sh"
[ -n "$session" ] || exit 0
case "$tool" in *seamtrail*) ;; *) exit 0 ;; esac

# SEAM-233: the ticket numbers tickets.sh keeps on this computer (numbers only) go with the call as chatTickets.
numbers=""
if [ -s "$data/tickets-$session.jsonl" ]; then numbers="$data/tickets-$session.jsonl"; fi
# The older Local harness reads the changed input from hookSpecificOutput; the Copilot harness from modifiedArgs.
both=1
if camel; then both=0; fi

# jq: on macOS 15 and later, and on most Linux machines.
if command -v jq >/dev/null 2>&1; then
  if [ -n "$numbers" ]; then set -- --slurpfile seen "$numbers"; else set -- --argjson seen '[]'; fi
  printf '%s' "$input" | jq -c --arg s "$session" --argjson both "$both" "$@" '
    (if has("toolArgs") then .toolArgs else .tool_input end) as $raw
    | (if $raw == null then {} elif ($raw | type) == "string" then (try ($raw | fromjson) catch null) else $raw end) as $args
    | select(($args | type) == "object")
    | ($seen | map(.k // []) | add // [] | unique | join(",")) as $keys
    | ($args + {chatId: $s} + (if $keys != "" then {chatTickets: $keys} else {} end)) as $new
    | {modifiedArgs: $new}
      + (if $both == 1 then {hookSpecificOutput: {hookEventName: "PreToolUse", updatedInput: $new}} else {} end)' 2>/dev/null
  exit 0
fi

# node: wherever it was installed (VS Code's own copy is not on the PATH).
if command -v node >/dev/null 2>&1; then
  printf '%s' "$input" | node -e '
    let s = ""; const [session, both, file] = process.argv.slice(1);
    process.stdin.on("data", (d) => (s += d)).on("end", () => {
      try {
        const d = JSON.parse(s);
        let args = "toolArgs" in d ? d.toolArgs : d.tool_input;
        if (args == null) args = {};
        if (typeof args === "string") { try { args = JSON.parse(args); } catch (e) { return; } }
        if (!args || typeof args !== "object" || Array.isArray(args)) return;
        const updated = Object.assign({}, args, { chatId: session });
        if (file) {
          try {
            const keys = new Set();
            for (const l of require("fs").readFileSync(file, "utf8").split("\n").filter(Boolean))
              for (const k of JSON.parse(l).k || []) keys.add(k);
            if (keys.size) updated.chatTickets = [...keys].sort().join(",");
          } catch (e) {}
        }
        const out = { modifiedArgs: updated };
        if (both === "1") out.hookSpecificOutput = { hookEventName: "PreToolUse", updatedInput: updated };
        process.stdout.write(JSON.stringify(out));
      } catch (e) {}
    });' "$session" "$both" "$numbers" 2>/dev/null
  exit 0
fi

# python3 — but not macOS's stand-in without the developer tools, which would open an install window.
py=$(command -v python3 2>/dev/null)
if [ -n "$py" ]; then
  if [ "$(uname)" = Darwin ] && [ "$py" = /usr/bin/python3 ] && ! xcode-select -p >/dev/null 2>&1; then exit 0; fi
  printf '%s' "$input" | "$py" -c '
import json, sys
session, both, path = sys.argv[1:4]
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
args = d["toolArgs"] if "toolArgs" in d else d.get("tool_input")
if args is None:
    args = {}
if isinstance(args, str):
    try:
        args = json.loads(args)
    except Exception:
        sys.exit(0)
if not isinstance(args, dict):
    sys.exit(0)
updated = dict(args)
updated["chatId"] = session
if path:
    try:
        with open(path) as f:
            keys = sorted({k for l in f if l.strip() for k in json.loads(l).get("k", [])})
        if keys:
            updated["chatTickets"] = ",".join(keys)
    except Exception:
        pass
out = {"modifiedArgs": updated}
if both == "1":
    out["hookSpecificOutput"] = {"hookEventName": "PreToolUse", "updatedInput": updated}
print(json.dumps(out))
' "$session" "$both" "$numbers" 2>/dev/null
fi
exit 0
