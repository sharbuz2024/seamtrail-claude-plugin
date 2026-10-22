#!/bin/sh
# SeamTrail · the tickets the chat talks about (SEAM-233). Keeps, on this computer only, the ticket numbers ("PAY-4")
# in the person's last 3 messages (`tickets.sh person`, from the message hook's `prompt`) and in Claude's last 3 replies
# (`tickets.sh claude`, from the turn-end hook's `last_assistant_message`) — the numbers only, never any text. The guard
# (guard.sh) sends them with the chat's SeamTrail calls, beside Claude's own one-line "working on", so SeamTrail can
# bring the chat the news about its work. Silent on any failure.

role="$1"
[ "$role" = person ] || [ "$role" = claude ] || exit 0
data="$CLAUDE_PLUGIN_DATA"
[ -n "$data" ] || exit 0
input=$(cat)
session=$(printf '%s' "$input" | grep -o '"session_id"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
[ -n "$session" ] || exit 0
mkdir -p "$data" 2>/dev/null || exit 0
# Nothing older than about a day stays on the computer either.
find "$data" -name 'tickets-*.jsonl' -mtime +1 -exec rm -f {} + 2>/dev/null
file="$data/tickets-$session.jsonl"
field=prompt
[ "$role" = claude ] && field=last_assistant_message

# jq: on macOS 15 and later, and on most Linux machines.
if command -v jq >/dev/null 2>&1; then
  entry=$(printf '%s' "$input" | jq -c --arg r "$role" --arg f "$field" '
    (.[$f] // "" | tostring) as $t
    | select($t | test("\\S"))
    | {r: $r, n: ($t | length), k: ([$t | match("\\b[A-Z][A-Z0-9]{1,9}-[0-9]{1,7}\\b"; "g").string] | unique)}' 2>/dev/null)
  [ -n "$entry" ] || exit 0
  # The newest 3 messages of each, in order; the same reply twice (a turn-end hook that ran again) counts once.
  tmp="$file.$$"
  { [ -f "$file" ] && cat "$file"; printf '%s\n' "$entry"; } | jq -cs '
    reduce .[] as $e ([]; if (map(select(.r == $e.r)) | last) == $e then . else . + [$e] end)
    | reverse
    | reduce .[] as $e ({p: 0, c: 0, out: []};
        if $e.r == "person" and .p < 3 then .p += 1 | .out += [$e]
        elif $e.r == "claude" and .c < 3 then .c += 1 | .out += [$e]
        else . end)
    | .out | reverse | .[]' > "$tmp" 2>/dev/null && mv "$tmp" "$file"
  rm -f "$tmp"
  exit 0
fi

# node, then python3: the same, for computers without jq.
if command -v node >/dev/null 2>&1; then
  printf '%s' "$input" | node -e '
    const fs = require("fs");
    const [role, field, file] = process.argv.slice(1);
    let s = ""; process.stdin.on("data", (d) => (s += d)).on("end", () => {
      try {
        const t = String(JSON.parse(s)[field] || "");
        if (!/\S/.test(t)) return;
        const e = { r: role, n: t.length, k: [...new Set(t.match(/\b[A-Z][A-Z0-9]{1,9}-[0-9]{1,7}\b/g) || [])].sort() };
        let all = [];
        try { all = fs.readFileSync(file, "utf8").split("\n").filter(Boolean).map((l) => JSON.parse(l)); } catch (x) {}
        const last = all.filter((x) => x.r === role).pop();
        if (!last || JSON.stringify(last) !== JSON.stringify(e)) all.push(e);
        const keep = []; const n = { person: 0, claude: 0 };
        for (const x of all.reverse()) if (n[x.r] < 3) { n[x.r] += 1; keep.push(x); }
        fs.writeFileSync(file, keep.reverse().map((x) => JSON.stringify(x)).join("\n") + "\n");
      } catch (x) {}
    });' "$role" "$field" "$file" 2>/dev/null
  exit 0
fi

py=$(command -v python3 2>/dev/null)
[ -n "$py" ] || exit 0
# Not macOS's stand-in without the developer tools, which would open an install window.
if [ "$(uname)" = Darwin ] && [ "$py" = /usr/bin/python3 ] && ! xcode-select -p >/dev/null 2>&1; then exit 0; fi
printf '%s' "$input" | "$py" -c '
import json, re, sys
role, field, path = sys.argv[1:4]
try:
    t = str(json.load(sys.stdin).get(field) or "")
except Exception:
    sys.exit(0)
if not re.search(r"\S", t):
    sys.exit(0)
e = {"r": role, "n": len(t), "k": sorted(set(re.findall(r"\b[A-Z][A-Z0-9]{1,9}-[0-9]{1,7}\b", t)))}
try:
    with open(path) as f:
        rows = [json.loads(l) for l in f if l.strip()]
except Exception:
    rows = []
last = [x for x in rows if x.get("r") == role][-1:]
if not last or last[0] != e:
    rows.append(e)
keep, n = [], {"person": 0, "claude": 0}
for x in reversed(rows):
    if n.get(x.get("r"), 3) < 3:
        n[x["r"]] += 1
        keep.append(x)
with open(path, "w") as f:
    f.write("".join(json.dumps(x) + "\n" for x in reversed(keep)))
' "$role" "$field" "$file" 2>/dev/null
exit 0
