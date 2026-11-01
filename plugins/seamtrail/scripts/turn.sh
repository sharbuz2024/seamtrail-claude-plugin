#!/bin/sh
# SeamTrail · at message end (SEAM-233; founder 2026-10-24: "hook .. should be on start of message and before ending
# message"; 2026-10-25: "build the plugin side on a branch"). When Claude finishes answering a message, sends SeamTrail
# a cut of what the person asked and of Claude's final reply, so SeamTrail keeps one row per message, with the notes
# and changes made for it (each SeamTrail call made for the message carries its id: message.sh makes it, guard.sh
# adds it).
#
# What leaves this computer: the chat id, the message's id, the ticket numbers the message and the reply name, and two
# cuts cleaned HERE, before they are sent — code blocks, secrets and credentials taken out (hint-rules.json), then the
# text itself when short, else its first 300 and last 200 characters and its links: "asked" is the cut message.sh made
# of the person's message, "did" the same cut of Claude's final reply. Sent once per message, at its first stop: when
# a turn-end hook (stop.sh's reminder) makes Claude go on, that second answer is not sent. Cleaning needs node or
# python3: without either, nothing is sent. The call runs in the background, so the chat never waits for it; silent on
# any failure, and an older SeamTrail without it answers "not found" and keeps nothing.

token="${CLAUDE_PLUGIN_OPTION_SEAMTRAIL_TOKEN:-$SEAMTRAIL_TOKEN}"
url="${CLAUDE_PLUGIN_OPTION_SEAMTRAIL_URL:-${SEAMTRAIL_URL:-https://mcp.seamtrail.com/mcp}}"
[ -n "$token" ] || exit 0
data="$CLAUDE_PLUGIN_DATA"
[ -n "$data" ] || exit 0
input=$(cat)
session=$(printf '%s' "$input" | grep -o '"session_id"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
[ -n "$session" ] || exit 0
turn="$data/turn-$session.json"
[ -s "$turn" ] || exit 0
# A second stop for the same message (a turn-end hook made Claude go on): not the real answer.
printf '%s' "$input" | grep -q '"stop_hook_active"[[:space:]]*:[[:space:]]*true' && exit 0
here=$(dirname "$0")

# The body {chat, messageId, asked, did, tickets}, from node, else python3 (not macOS's stand-in without the developer
# tools, which would open an install window).
body=""
if command -v node >/dev/null 2>&1; then
  body=$(printf '%s' "$input" | node -e '
    const fs = require("fs"), cp = require("child_process");
    const [file, dir] = process.argv.slice(1);
    let s = ""; process.stdin.on("data", (d) => (s += d)).on("end", () => {
      try {
        const d = JSON.parse(s), t = JSON.parse(fs.readFileSync(file, "utf8"));
        const chat = String(d.session_id || ""), id = String(t.messageId || "");
        if (!chat || !/^[A-Za-z0-9_-]{8,100}$/.test(id)) return;
        const keys = new Set(String(t.tickets || "").split(",").filter(Boolean));
        let did = null;
        const reply = typeof d.last_assistant_message === "string" ? d.last_assistant_message : "";
        if (/\S/.test(reply)) {
          try {
            const out = JSON.parse(String(cp.execFileSync(process.execPath, [dir + "/hint.js", dir + "/hint-rules.json"],
              { input: JSON.stringify({ session_id: chat, prompt: reply }), timeout: 3000 })));
            did = out.hint || null;
            for (const k of String(out.tickets || "").split(",").filter(Boolean)) keys.add(k);
          } catch (e) {}
        }
        const asked = typeof t.hint === "string" && t.hint ? t.hint : null;
        if (!asked && !did && !keys.size) return;
        process.stdout.write(JSON.stringify({ chat, messageId: id, asked, did, tickets: [...keys].sort().join(",") }));
      } catch (e) {}
    });' "$turn" "$here" 2>/dev/null)
else
  py=$(command -v python3 2>/dev/null)
  if [ -n "$py" ] && ! { [ "$(uname)" = Darwin ] && [ "$py" = /usr/bin/python3 ] && ! xcode-select -p >/dev/null 2>&1; }; then
    body=$(printf '%s' "$input" | "$py" -I -c '
import json, re, subprocess, sys
path, here = sys.argv[1], sys.argv[2]
try:
    d = json.load(sys.stdin)
    with open(path) as f:
        t = json.load(f)
except Exception:
    sys.exit(0)
chat, mid = str(d.get("session_id") or ""), str(t.get("messageId") or "")
if not chat or not re.fullmatch(r"[A-Za-z0-9_-]{8,100}", mid):
    sys.exit(0)
keys = {k for k in str(t.get("tickets") or "").split(",") if k}
did = None
reply = d.get("last_assistant_message")
if isinstance(reply, str) and reply.strip():
    try:
        out = json.loads(subprocess.run([sys.executable, "-I", here + "/hint.py", here + "/hint-rules.json"],
                                        input=json.dumps({"session_id": chat, "prompt": reply}),
                                        capture_output=True, text=True, timeout=3).stdout)
        did = out.get("hint") or None
        keys |= {k for k in str(out.get("tickets") or "").split(",") if k}
    except Exception:
        pass
asked = t.get("hint") if isinstance(t.get("hint"), str) and t.get("hint") else None
if asked or did or keys:
    print(json.dumps({"chat": chat, "messageId": mid, "asked": asked, "did": did, "tickets": ",".join(sorted(keys))},
                     separators=(",", ":"), ensure_ascii=False))
' "$turn" "$here" 2>/dev/null)
  fi
fi
[ -n "$body" ] || exit 0

# Once per message: the id is marked sent before the call goes.
mid=$(printf '%s' "$body" | grep -o '"messageId"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
[ -n "$mid" ] || exit 0
sent="$data/turn-$session.sent"
[ "$(cat "$sent" 2>/dev/null)" = "$mid" ] && exit 0
printf '%s' "$mid" > "$sent" 2>/dev/null || exit 0

# In the background, its output nowhere, so the chat never waits for it.
tmp=$(mktemp 2>/dev/null) || exit 0
printf '%s' "$body" > "$tmp"
(
  curl -s --max-time 5 -X POST "${url%/}/hook/turn" \
    -H "Authorization: Bearer $token" -H 'Content-Type: application/json' --data-binary @"$tmp" -o /dev/null 2>/dev/null
  rm -f "$tmp"
) >/dev/null 2>&1 </dev/null &
exit 0
