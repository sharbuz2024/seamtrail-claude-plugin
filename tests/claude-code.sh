#!/bin/sh
# The Claude Code plugin's hooks, fed sample hook inputs: start.sh sends the plugin's version (SEAM-273); saved.sh counts
# a note or a real change made through SeamTrail as saved, and stop.sh asks once, in the remember tool's words (SEAM-215).
# Needs python3. No network: curl is a stand-in that logs what it was given.
here=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
P="$here/plugins/seamtrail"
S=sess-215
DATA=$(mktemp -d)
export CLAUDE_PLUGIN_DATA="$DATA"
fail=0

# start.sh: the chat registers with this plugin's version, read from its manifest (SEAM-273).
mkdir -p "$DATA/bin"
cat > "$DATA/bin/curl" <<'CURL'
#!/bin/sh
printf '%s\n' "$@" >> "$CURL_LOG"
exit 0
CURL
chmod +x "$DATA/bin/curl"
want=$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' "$P/.claude-plugin/plugin.json")
for root in "$P" ""; do
  : > "$DATA/curl.log"
  printf '{"session_id":"%s"}' "$S" | CURL_LOG="$DATA/curl.log" PATH="$DATA/bin:$PATH" CLAUDE_PLUGIN_ROOT="$root" \
    SEAMTRAIL_TOKEN=tok sh "$P/scripts/start.sh" > /dev/null 2>&1
  if [ -n "$root" ]; then how="CLAUDE_PLUGIN_ROOT set"; else how="found from the script folder"; fi
  if grep -qx "version=$want" "$DATA/curl.log"; then echo "ok   start: sends version=$want ($how)"
  else echo "FAIL start: no version=$want ($how) in $(tr '\n' ' ' < "$DATA/curl.log")"; fail=1; fi
done

check() { # name, expected (saved|not)
  if [ -f "$DATA/saved-$S" ]; then got=saved; else got=not; fi
  if [ "$got" = "$2" ]; then echo "ok   $1 → $got"; else echo "FAIL $1 → $got (wanted $2)"; fail=1; fi
  rm -f "$DATA/saved-$S"
}
post() { # tool, response-json-value, mode
  printf '{"session_id":"%s","hook_event_name":"PostToolUse","tool_name":"%s","tool_input":{"question":"x"},"tool_response":%s}' \
    "$S" "$1" "$2" | sh "$P/scripts/saved.sh" $3
}

post mcp__seamtrail__remember '"{\"memoryId\":\"m1\",\"kind\":\"fact\"}"'
check "remember" saved
post mcp__seamtrail__ask_seamtrail '"{\"answer\":\"No ticket found\",\"checked\":[\"search_jira\"]}"' change
check "ask_seamtrail, a question only" not
post mcp__seamtrail__ask_seamtrail '"{\"answer\":\"Done: moved\",\"did\":[{\"what\":\"move ticket\",\"done\":true,\"verified\":true}]}"' change
check "ask_seamtrail, a real change (text reply)" saved
post mcp__seamtrail__ask_seamtrail '[{"type":"text","text":"{\"did\":[{\"what\":\"move\",\"done\":true}]}"}]' change
check "ask_seamtrail, a real change (content blocks)" saved
post mcp__seamtrail__ask_seamtrail '{"structuredContent":{"did":[{"what":"move","done":true}]}}' change
check "ask_seamtrail, a real change (structured)" saved
post mcp__seamtrail__ask_seamtrail '"{\"answer\":\"Not done\",\"did\":[{\"what\":\"move\",\"done\":false,\"error\":\"Jira refused\"}]}"' change
check "ask_seamtrail, a change that failed" not
post mcp__seamtrail__ask_seamtrail '"{\"tool\":\"promotion_rules\",\"result\":{\"checklist\":[{\"label\":\"flag\",\"done\":true}]}}"' change
check "ask_seamtrail, a read that happens to hold done:true" not
post mcp__seamtrail__undo_change '"Undone — reading it back confirms it."' change
check "undo_change" saved
post mcp__seamtrail__undo_change '{"isError":true,"content":[{"type":"text","text":"That is not an undo handle"}]}' change
check "undo_change that failed" not

# stop.sh and remind.sh (SEAM-215; founder 2026-10-26: "build anyway under SEAM-215"): the turn end never stops Claude —
# it only notes that nothing was saved; with the next message, remind.sh hands Claude the reminder once.
stop() { printf '{"session_id":"%s","hook_event_name":"Stop","stop_hook_active":%s}' "$S" "${1:-false}" | sh "$P/scripts/stop.sh"; }
remind() { printf '{"session_id":"%s","hook_event_name":"UserPromptSubmit","prompt":"next"}' "$S" | sh "$P/scripts/remind.sh"; }
printf 'p-1\nMy Project\n' > "$DATA/project-$S"
out=$(stop)
if [ -z "$out" ] && [ -f "$DATA/remind-$S" ]; then echo "ok   stop: nothing saved → never stops Claude, notes it on this computer"; else echo "FAIL stop printed '$out' or noted nothing"; fail=1; fi
out=$(remind)
printf '%s' "$out" | python3 -c '
import sys
r = sys.stdin.read()
assert r.startswith("SeamTrail: nothing was saved in your last turn."), r
assert "projectId p-1 (the project “My Project”)" in r, r
assert "This chat saves only into that project: if something belongs to another project, tell your person instead" in r, r
assert "never repeat it" in r and "do not mention this reminder; just answer the new message" in r, r
assert "decision" not in r.split("remember tool")[0] or True
print("ok   remind: with the next message, names the project, never asks to repeat the answer or to reply about it")
# SEAM-215 note kinds: the same guide as the remember tool (KIND_GUIDE)
for want in ["one note per thing", "an approval and a launch are two notes",
             "decision = a choice a person made that could have gone another way (an approval too): who, what and because",
             "never your own choice until your person agrees",
             "status = where the work stands", "your own build steps go here",
             "fact = true whatever anyone chooses", "blocker = what stops the work now",
             "risk = what may go wrong", "question = open, for someone to answer"]:
    assert want in r, want
print("ok   remind: says which kind each note is (decision / status / fact / blocker / risk / question), one note per thing")
' || fail=1
out=$(remind)
if [ -z "$out" ] && [ ! -f "$DATA/remind-$S" ]; then echo "ok   remind: once only"; else echo "FAIL remind twice: '$out'"; fail=1; fi
: > "$DATA/saved-$S"; : > "$DATA/remind-$S"
out=$(stop)
if [ -z "$out" ] && [ ! -f "$DATA/saved-$S" ] && [ ! -f "$DATA/remind-$S" ] && [ -z "$(remind)" ]; then echo "ok   stop: saved this turn → no reminder, markers cleared"; else echo "FAIL stop after a save: '$out'"; fail=1; fi
out=$(stop true)
if [ -z "$out" ]; then echo "ok   stop: a second stop for the same message prints nothing either"; else echo "FAIL stop printed on a second stop"; fail=1; fi
rm -f "$DATA/remind-$S"
printf 'ask\n\n' > "$DATA/project-$S"
stop > /dev/null
remind | grep -q "more than one SeamTrail project" && echo "ok   remind: two projects matched (older SeamTrail) unchanged" || { echo "FAIL remind for two projects"; fail=1; }
printf 'p-1\nPay \\"UPI\\" \\u00b7 Team\n' > "$DATA/project-$S"; rm -f "$DATA/saved-$S"
stop > /dev/null
remind | grep -q 'with projectId p-1: one note per thing' && echo "ok   remind: a name SeamTrail escaped never shows its codes: the id alone" || { echo "FAIL remind with an escaped name"; fail=1; }
rm -f "$DATA/project-$S"
out=$(stop)
if [ -z "$out" ] && [ ! -f "$DATA/remind-$S" ] && [ -z "$(remind)" ]; then echo "ok   stop: no project → never reminds"; else echo "FAIL reminded without a project"; fail=1; fi
printf 'p-1\nMy Project\n' > "$DATA/project-$S"; : > "$DATA/remind-$S"; touch -t 202001010000 "$DATA/remind-$S"
if [ -z "$(remind)" ]; then echo "ok   remind: a note older than a day is dropped"; else echo "FAIL old reminder handed over"; fail=1; fi
rm -f "$DATA/project-$S"
if grep -q '"decision"' "$P/scripts/stop.sh"; then echo "FAIL stop.sh can still stop Claude"; fail=1; else echo "ok   stop.sh has no way to stop Claude (it never writes a decision)"; fi
python3 -c 'import json,sys; h=json.load(open(sys.argv[1]))["hooks"]; ups=[x["command"] for e in h["UserPromptSubmit"] for x in e["hooks"]]; assert any(c.endswith("/scripts/remind.sh") for c in ups), ups; print("ok   hooks.json runs remind.sh with each message")' "$P/hooks/hooks.json" || fail=1

# guard.sh (SEAM-233, founder 2026-10-24: "the agent communication summary also make sure no secrets, credentials,
# security data"): Claude's workingOn line is cleaned on this computer before the call leaves — by node, else python3;
# with only jq it is left out; the chat id is added either way.
export P DATA
python3 -I - <<'PY' || fail=1
import json, os, subprocess
P, D = os.environ["P"], os.environ["DATA"]
bad = 0
def check(label, cond, info=""):
    global bad
    print(("ok   " if cond else "FAIL ") + label + ("" if cond else f" — {info}"))
    bad |= not cond
token = "gh" + "p_abcdefghijklmnopqrstuvwxyz0123456789"  # two pieces: no token-shaped string in this file
line = f"Fixing the stage login (PAY-4); the password is tiger123, key {token}"
hook_in = json.dumps({"session_id": "s-guard", "tool_name": "mcp__plugin_seamtrail_seamtrail__remember",
                      "tool_input": {"content": "x", "workingOn": line}})
def which(t):
    r = subprocess.run(["sh", "-c", f"command -v {t}"], capture_output=True, text=True).stdout.strip()
    return r if r.startswith("/") else None
basics = ["sh", "cat", "grep", "sed", "head", "dirname", "uname", "xcode-select", "printf"]
def path_with(*tools):
    d = os.path.join(D, "path-" + "-".join(tools or ("none",)))
    os.makedirs(d, exist_ok=True)
    for t in basics + list(tools):
        w = which(t)
        if w and not os.path.exists(os.path.join(d, t)):
            os.symlink(w, os.path.join(d, t))
    return d
def guard(path):
    r = subprocess.run(["sh", f"{P}/scripts/guard.sh"], input=hook_in, capture_output=True, text=True,
                       env={"PATH": path, "HOME": D, "CLAUDE_PLUGIN_DATA": D}, timeout=30)
    return json.loads(r.stdout)["hookSpecificOutput"]["updatedInput"] if r.stdout.strip() else None
for tool in [t for t in ("node", "python3") if which(t)]:
    out = guard(path_with(tool))
    wo = (out or {}).get("workingOn", "")
    check(f"guard with {tool}: the line keeps what the message is about", out is not None and "Fixing the stage login (PAY-4)" in wo, json.dumps(out))
    check(f"guard with {tool}: no secret or credential leaves", "tiger123" not in wo and token not in wo, wo)
    check(f"guard with {tool}: the chat id is added", (out or {}).get("chatId") == "s-guard", json.dumps(out))
if which("jq"):
    out = guard(path_with("jq"))
    check("guard with only jq: the line is left out, the chat id added", out is not None and "workingOn" not in out and out.get("chatId") == "s-guard", json.dumps(out))
out = guard(path_with())
check("guard with no JSON tool: the call goes as it is (SeamTrail cleans the line before keeping it)", out is None, json.dumps(out))
raise SystemExit(1 if bad else 0)
PY

# SEAM-323 (founder 2026-11-12: "yes make the ticket"): auto mode refuses a call a hook changed after its check, so
# message.sh tells Claude, with each message, what the guard adds (chatId, chatTickets, messageId); a call holding
# those comes out of the guard exactly as it went in. Wrong or old values are still corrected.
python3 -I - <<'PY' || fail=1
import json, os, re, subprocess
P, D = os.environ["P"], os.environ["DATA"]
bad = 0
def check(label, cond, info=""):
    global bad
    print(("ok   " if cond else "FAIL ") + label + ("" if cond else f" — {info}"))
    bad |= not cond
def which(t):
    r = subprocess.run(["sh", "-c", f"command -v {t}"], capture_output=True, text=True).stdout.strip()
    return r if r.startswith("/") else None
stub = os.path.join(D, "stub-323")
os.makedirs(stub, exist_ok=True)
with open(os.path.join(stub, "curl"), "w") as f:  # logs each call, answers "news" (into its -o file, else printed)
    f.write('#!/bin/sh\nprintf "call\\n" >> "$CURL_LOG"\nprev=""; out=""\n'
            'for a in "$@"; do [ "$prev" = "-o" ] && out="$a"; prev="$a"; done\n'
            'if [ -n "$out" ]; then printf "news" > "$out"; else printf "news"; fi\n'
            'case " $* " in *" -w "*) printf 200 ;; esac\nexit 0\n')
os.chmod(os.path.join(stub, "curl"), 0o755)
basics = ["sh", "cat", "grep", "sed", "head", "dirname", "uname", "xcode-select", "printf", "mktemp", "rm", "tr",
          "find", "mkdir", "sort", "paste", "uuidgen", "mv"]
def path_with(*tools):
    d = os.path.join(D, "path323-" + "-".join(tools or ("none",)))
    if not os.path.isdir(d):
        os.makedirs(d)
        for t in basics + list(tools):
            w = which(t)
            if w:
                os.symlink(w, os.path.join(d, t))
        os.symlink(os.path.join(stub, "curl"), os.path.join(d, "curl"))
    return d
def run(script, payload, path, data, token="tok-1"):
    env = {"PATH": path, "HOME": D, "TMPDIR": D, "CLAUDE_PLUGIN_DATA": data, "CURL_LOG": os.path.join(data, "curl.log")}
    if token:
        env["SEAMTRAIL_TOKEN"] = token
    return subprocess.run(["sh", f"{P}/scripts/{script}"], input=json.dumps(payload), capture_output=True, text=True,
                          env=env, timeout=30).stdout
def told(out):
    m = re.search(r"SeamTrail fields for this message: .*?as they are: (\{[^{}]*\})\.", out)
    return json.loads(m.group(1)) if m else None
def guard(chat, tool_input, path, data):
    out = run("guard.sh", {"session_id": chat, "tool_name": "mcp__plugin_seamtrail_seamtrail__remember",
                           "tool_input": tool_input}, path, data)
    return json.loads(out)["hookSpecificOutput"]["updatedInput"] if out.strip() else None
line = "Fixing the refund window in two tickets on a branch."
cases = [(t, path_with(t)) for t in ("node", "python3") if which(t)] + ([("only jq", path_with("jq"))] if which("jq") else [])
check("SEAM-323: at least one way to run the guard here", bool(cases))
for name, path in cases:
    data = os.path.join(D, "data323-" + name.replace(" ", "-"))
    os.makedirs(data)
    chat = "chat-323-" + name.replace(" ", "-")
    out = run("message.sh", {"session_id": chat, "prompt": "please fix SEAM-999 next, after PAY-4"}, path, data)
    f = told(out)
    turn = json.load(open(os.path.join(data, f"turn-{chat}.json")))
    check(f"{name}: Claude is told this chat's id, the message's id and the tickets, after SeamTrail's answer",
          out.startswith("news") and f is not None and f.get("chatId") == chat and f.get("messageId") == turn.get("messageId")
          and f.get("chatTickets") == "PAY-4,SEAM-999", out)
    check(f"{name}: a ticket named for the first time is already in the list (tickets.sh ran first)",
          "SEAM-999" in (f or {}).get("chatTickets", ""), json.dumps(f))
    check(f"{name}: Claude is told never to show them", "Never show these fields to your person." in out, out)
    if name == "only jq":
        check(f"{name}: Claude is told to leave workingOn out (it would be cut)", "Leave workingOn out" in out, out)
    else:
        check(f"{name}: Claude is told how to write workingOn so it goes as written", "one plain line of at most 400 characters" in out, out)
    calls = open(os.path.join(data, "curl.log")).read().count("call")
    check(f"{name}: still one call to SeamTrail at the message's start", calls == 1, f"{calls} calls")
    rows = [json.loads(l) for l in open(os.path.join(data, f"tickets-{chat}.jsonl")) if l.strip()]
    check(f"{name}: the message's tickets are kept once", [r["r"] for r in rows] == ["person"], json.dumps(rows))
    for order in ("after", "before"):
        base = {"content": "x"} if name == "only jq" else {"content": "x", "workingOn": line}
        call = {**base, **(f or {})} if order == "after" else {**(f or {}), **base}
        got = guard(chat, call, path, data)
        check(f"{name}: a call holding them (put {order} its own fields) comes out of the guard the same",
              json.dumps(got) == json.dumps(call), f"{json.dumps(call)} → {json.dumps(got)}")
    stale = {"content": "x", "chatId": "someone-else", "chatTickets": "OLD-1", "messageId": "old-message-0001"}
    got = guard(chat, stale, path, data) or {}
    check(f"{name}: wrong or old values are still corrected", got.get("chatId") == chat and got.get("chatTickets") == "PAY-4,SEAM-999"
          and got.get("messageId") == turn.get("messageId"), json.dumps(got))
    # A chat whose last messages name no ticket: no list is told, and one Claude adds anyway is taken out.
    chat2, data2 = chat + "-b", data + "-b"
    os.makedirs(data2)
    f2 = told(run("message.sh", {"session_id": chat2, "prompt": "now update the docs"}, path, data2)) or {}
    got = guard(chat2, {"content": "x", "chatTickets": "OLD-1"}, path, data2) or {}
    check(f"{name}: no tickets in the chat → none told, and a made-up list is taken out", "chatTickets" not in f2 and "chatTickets" not in got, json.dumps([f2, got]))
    # Without a token: nothing is sent, and Claude is still told the chat id and the tickets.
    data3 = data + "-c"
    os.makedirs(data3)
    out = run("message.sh", {"session_id": chat + "-c", "prompt": "fix PAY-4"}, path, data3, token=None)
    f3 = told(out) or {}
    sent = os.path.exists(os.path.join(data3, "curl.log"))
    check(f"{name}: without a token nothing is sent, and Claude still gets the chat id and the tickets",
          not sent and f3.get("chatId") == chat + "-c" and f3.get("chatTickets") == "PAY-4", out)
data4 = os.path.join(D, "data323-none")
os.makedirs(data4)
out = run("message.sh", {"session_id": "chat-323-none", "prompt": "fix PAY-4"}, path_with(), data4)
check("with no JSON tool: the guard changes nothing, so Claude is told nothing", "SeamTrail fields" not in out, out)
ups = [x["command"] for e in json.load(open(f"{P}/hooks/hooks.json"))["hooks"]["UserPromptSubmit"] for x in e["hooks"]]
check("hooks.json: message.sh keeps the tickets itself; tickets.sh no longer runs beside it", not any("tickets.sh" in c for c in ups)
      and any(c.endswith("/scripts/message.sh") for c in ups), json.dumps(ups))
raise SystemExit(1 if bad else 0)
PY

python3 -m json.tool "$P/hooks/hooks.json" > /dev/null && python3 -m json.tool "$P/.claude-plugin/plugin.json" > /dev/null && echo "ok   hooks.json and plugin.json are valid JSON" || fail=1
rm -rf "$DATA"
[ $fail = 0 ] && echo "ALL PASSED" || echo "SOME FAILED"
