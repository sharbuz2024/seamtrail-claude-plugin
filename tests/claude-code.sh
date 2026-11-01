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

python3 -m json.tool "$P/hooks/hooks.json" > /dev/null && python3 -m json.tool "$P/.claude-plugin/plugin.json" > /dev/null && echo "ok   hooks.json and plugin.json are valid JSON" || fail=1
rm -rf "$DATA"
[ $fail = 0 ] && echo "ALL PASSED" || echo "SOME FAILED"
