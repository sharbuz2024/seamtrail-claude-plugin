#!/bin/sh
# SEAM-254 · the SeamTrail plugin for the Devin CLI (plugins/seamtrail-devin), fed sample hook inputs in Devin's
# documented format (docs.devin.ai/cli/extensibility/hooks/lifecycle-hooks: session_id, prompt_id, prompt,
# tool_name/tool_input, tool_response {success, output, error}, stop_hook_active, last_assistant_message). Every hook
# runs through the plugin's hooks.json the way Devin runs it: its matcher (a regex on tool_name) picks it, and `sh -c`
# runs its command with DEVIN_PLUGIN_ROOT set. curl is a stand-in that records its arguments and answers from files,
# so nothing reaches SeamTrail; HOME and the state folders point into a temporary folder. Needs python3 and git.
# Run: sh tests/devin.sh

R=$(cd "$(dirname "$0")/.." && pwd)
P="$R/plugins/seamtrail-devin"
T=$(mktemp -d "${TMPDIR:-/tmp}/seamtrail-devin-test.XXXXXX") || exit 1
trap 'rm -rf "$T"' EXIT
fail=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }
is() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 — got '$2', wanted '$3'"; fi; }

export HOME="$T/home" XDG_STATE_HOME="$T/state" PLUGIN_DATA="$T/data" DEVIN_PLUGIN_ROOT="$P"
export SEAMTRAIL_TOKEN=tok-254 SEAMTRAIL_URL=https://seamtrail.invalid/mcp
unset CLAUDE_PLUGIN_DATA CLAUDE_PLUGIN_ROOT CLAUDE_PLUGIN_OPTION_SEAMTRAIL_TOKEN PLUGIN_ROOT
mkdir -p "$HOME" "$T/bin"
DATA="$PLUGIN_DATA"
S=3f8d1c2a-1111-4222-8333-944455556666

# The stand-in curl: writes each argument on its own line to $T/curl.log, answers with $T/headers and $T/body.
cat > "$T/bin/curl" <<'EOF'
#!/bin/sh
for a in "$@"; do printf '%s\n' "$a"; done >> "$FAKE_DIR/curl.log"
out=""; hdr=""
while [ $# -gt 0 ]; do
  case "$1" in -o) out="$2"; shift ;; -D) hdr="$2"; shift ;; esac
  shift
done
[ -f "$FAKE_DIR/curl.fail" ] && exit 22
[ -n "$hdr" ] && cat "$FAKE_DIR/headers" > "$hdr"
if [ -n "$out" ]; then cat "$FAKE_DIR/body" > "$out"; else cat "$FAKE_DIR/body"; fi
exit 0
EOF
chmod +x "$T/bin/curl"
export FAKE_DIR="$T" PATH="$T/bin:$PATH"
called() { grep -Fxq -- "$1" "$T/curl.log" 2>/dev/null; }

# The commands hooks.json runs for an event (and a tool name), one per line: a matcher is a regex on tool_name, and no
# matcher matches every tool. HOOK_PATH, when set, is the only PATH the hook gets (to try jq, node, python3, none).
commands() {
  python3 -c '
import json, re, sys
for entry in json.load(open(sys.argv[1])).get(sys.argv[2], []):
    m = entry.get("matcher") or ""
    if m and not re.search(m, sys.argv[3]):
        continue
    for h in entry["hooks"]:
        print(h["command"])
' "$P/hooks.json" "$1" "${2-}"
}
hook() { # event, tool name ("" for none), stdin JSON → the hooks' stdout
  commands "$1" "$2" > "$T/cmds"
  while IFS= read -r c; do
    if [ -n "$HOOK_PATH" ]; then
      printf '%s' "$3" | env PATH="$HOOK_PATH" /bin/sh -c "$c" || bad "hook exited with an error: $c"
    else
      printf '%s' "$3" | sh -c "$c" || bad "hook exited with an error: $c"
    fi
  done < "$T/cmds"
}

echo "— the plugin's files"
python3 - "$P" <<'EOF' || bad "the plugin's files (see the error above)"
import json, os, re, sys
p = sys.argv[1]
m = json.load(open(os.path.join(p, ".devin-plugin/plugin.json")))
assert re.fullmatch(r"[a-z0-9]+([-.][a-z0-9]+)*", m["name"]), m["name"]
assert m.get("skills") == [], "no skills: the plugin is hooks and the MCP server"
h = json.load(open(os.path.join(p, "hooks.json")))
events = {"PreToolUse", "PostToolUse", "PermissionRequest", "UserPromptSubmit", "Stop", "PostCompaction",
          "SessionStart", "SessionEnd"}
assert set(h) <= events, set(h) - events   # Devin's plugin hooks.json is the hooks object itself, no "hooks" key
for ev, entries in h.items():
    for e in entries:
        for k in e["hooks"]:
            assert k["type"] == "command" and isinstance(k["timeout"], int), k
            s = re.fullmatch(r'sh "\$DEVIN_PLUGIN_ROOT/scripts/([a-z]+\.sh)"( person| claude| change)?', k["command"])
            assert s and os.path.isfile(os.path.join(p, "scripts", s.group(1))), k["command"]
mcp = json.load(open(os.path.join(p, ".mcp.json")))["mcpServers"]["seamtrail"]
assert mcp["url"] == "https://mcp.seamtrail.com/mcp" and mcp.get("transport") == "http", mcp
assert "headers" not in mcp, "no token in the plugin: Devin signs in to SeamTrail with OAuth"
print("ok   plugin.json, hooks.json and .mcp.json: valid, Devin's layout, every command finds its script")
EOF
for f in "$P"/scripts/*.sh; do sh -n "$f" || bad "sh -n $f"; done

echo "— which hook runs for which tool"
python3 - "$P/hooks.json" <<'EOF' || bad "matchers (see the error above)"
import json, re, sys
h = json.load(open(sys.argv[1]))
def picked(event, tool, match):
    return [k["command"].split("/scripts/")[1] for e in h.get(event, []) if not e.get("matcher") or match(e["matcher"], tool)
            for k in e["hooks"]]
want = {"remember": ['saved.sh"'], "resolve": ['saved.sh"'], "settle_question": ['saved.sh"'],
        "widen_memory": ['saved.sh"'], "ask_seamtrail": ['saved.sh" change'], "undo_change": ['saved.sh" change'],
        "set_chat_project": ['picked.sh"'], "search_memory": [], "project_context": []}
# Devin's docs say "a regex matched against tool_name": both a search and a whole-name match must pick the same hooks.
for match in (re.search, re.fullmatch):
    for tool, w in want.items():
        got = picked("PostToolUse", "mcp__seamtrail__" + tool, match)
        assert got == w, (match.__name__, tool, got)
    assert picked("PreToolUse", "mcp__seamtrail__search_memory", match) == ['guard.sh"']
    assert picked("PreToolUse", "exec", match) == []
print("ok   PostToolUse: the saved marker, the change rule and the picked project each on their own tools; guard on MCP tools only")
EOF

echo "— chat start (SessionStart)"
git -c init.defaultBranch=main init -q "$T/repo" && git -C "$T/repo" remote add origin https://github.com/acme/pay.git \
  && git -C "$T/repo" -c user.name=t -c user.email=t@example.com commit -q --allow-empty -m init \
  && git -C "$T/repo" checkout -q -b seam-254-devin || bad "test repository"
export DEVIN_PROJECT_DIR="$T/repo"
printf 'SeamTrail · the project “Payments”\n\tDecided: pay with "UPI" first — see C:\\pay\\upi\r\nA bell\007 rings ✓\n' > "$T/body"
printf 'HTTP/2 200\r\ncontent-type: text/plain\r\nx-seamtrail-project: 11111111-2222-3333-4444-555555555555\r\nx-seamtrail-project-name: Payments\r\n\r\n' > "$T/headers"
mkdir -p "$DATA" && : > "$DATA/saved-$S"
in_start='{"hook_event_name":"SessionStart","session_id":"'$S'","source":"startup"}'
rm -f "$T/curl.log"
hook SessionStart "" "$in_start" > "$T/out"
python3 - "$T/out" "$T/body" <<'EOF' || bad "start: the context Devin gets (see the error above): $(cat "$T/out")"
import json, sys
d = json.load(open(sys.argv[1]))
body = open(sys.argv[2], encoding="utf-8", newline="").read()
o = d["hookSpecificOutput"]
assert o["hookEventName"] == "SessionStart", o
assert o["additionalContext"] == body.rstrip("\n").replace("\x07", ""), repr(o["additionalContext"])
print("ok   start: SeamTrail's text handed to Devin as additionalContext — quotes, backslashes, tab, CR, ✓ intact")
EOF
miss=""
for a in https://seamtrail.invalid/mcp/hook/start "Authorization: Bearer tok-254" assistant=devin "chat=$S" \
  "folder=$T/repo" remote=https://github.com/acme/pay.git branch=seam-254-devin chatName=; do
  called "$a" || miss="$miss '$a'"
done
is "start: assistant=devin, chat id, folder, remote and branch sent with the token (missing:)" "$miss" ""
is "start: the chat's project kept (id, name)" "$(cat "$DATA/project-$S" 2>/dev/null | paste -sd'|' -)" \
  "11111111-2222-3333-4444-555555555555|Payments"
[ -f "$DATA/saved-$S" ] && bad "start: an old saved marker survived" || ok "start: a new chat starts with nothing saved"

rm -f "$T/curl.log"
out=$(SEAMTRAIL_TOKEN=; hook SessionStart "" "$in_start")
if [ -z "$out" ] && [ ! -f "$T/curl.log" ] && [ ! -f "$DATA/project-$S" ]; then ok "start: no token → silent, nothing sent, no project"; else bad "start without a token: '$out'"; fi
: > "$T/curl.fail"
out=$(hook SessionStart "" "$in_start")
rm -f "$T/curl.fail"
if [ -z "$out" ] && [ ! -f "$DATA/project-$S" ]; then ok "start: SeamTrail unreachable → silent"; else bad "start when curl fails: '$out'"; fi
: > "$T/body"
out=$(hook SessionStart "" "$in_start")
if [ -z "$out" ] && [ -f "$DATA/project-$S" ]; then ok "start: empty answer → nothing added, project still kept"; else bad "start with an empty answer: '$out'"; fi

echo "— every message (UserPromptSubmit)"
printf 'News: PAY-4 moved to Done by Priya.\nStill true: "pay with UPI" (decided 21 Oct).\n' > "$T/body"
in_msg='{"hook_event_name":"UserPromptSubmit","session_id":"'$S'","prompt":"Fix PAY-4 and SEAM-254 now; not pay-5 or X-1.\nAlso \"ABC-12\" please, my secret words","prompt_id":"B71E9D40-1234-4ABC-8DEF-001122334455"}'
rm -f "$T/curl.log" "$DATA/tickets-$S.jsonl"
hook UserPromptSubmit "" "$in_msg" > "$T/out"
python3 - "$T/out" "$T/body" <<'EOF' || bad "message: the context Devin gets (see the error above): $(cat "$T/out")"
import json, sys
o = json.load(open(sys.argv[1]))["hookSpecificOutput"]
assert o["hookEventName"] == "UserPromptSubmit", o
assert o["additionalContext"] == open(sys.argv[2]).read().rstrip("\n"), repr(o["additionalContext"])
print("ok   message: SeamTrail's news handed to Devin as additionalContext")
EOF
called https://seamtrail.invalid/mcp/hook/message && called "chat=$S" && called "tickets=ABC-12,PAY-4,SEAM-254" \
  && ok "message: only the chat id and the message's ticket numbers sent (not prompt_id, not pay-5 or X-1)" \
  || bad "message: curl got: $(paste -sd' ' - < "$T/curl.log")"
grep -q -e secret -e Fix "$T/curl.log" && bad "message: the person's words left the computer" || ok "message: the person's words never sent"
is "message: tickets.sh kept the message's numbers" \
  "$(python3 -c 'import json,sys; r=json.loads(open(sys.argv[1]).readline()); print(r["r"], ",".join(r["k"]))' "$DATA/tickets-$S.jsonl")" \
  "person ABC-12,PAY-4,SEAM-254"
: > "$T/body"
is "message: nothing to tell → nothing added" "$(hook UserPromptSubmit "" "$in_msg")" ""
rm -f "$T/curl.log"
is "message: no token → nothing sent, nothing added" "$(SEAMTRAIL_TOKEN=; hook UserPromptSubmit "" "$in_msg")$(cat "$T/curl.log" 2>/dev/null)" ""

echo "— ticket numbers of the last 3 messages each way (tickets.sh), and the guard (PreToolUse), with jq, node, python3, none"
mkdir -p "$T/base" "$T/only-jq" "$T/only-node" "$T/only-python3" "$T/only-none"
for t in sh cat grep head sed mkdir rm mv tr awk uname xcode-select dirname find paste sort mktemp; do
  w=$(command -v "$t") && ln -sf "$w" "$T/base/$t"
done
for t in jq node python3; do w=$(command -v "$t") && ln -sf "$w" "$T/only-$t/$t"; done
pre() { printf '{"hook_event_name":"PreToolUse","tool_name":"%s","tool_input":{"query":"upi","projectId":"p-1"},"session_id":"%s","prompt_id":"q-1"}' "$1" "$2"; }
stop_in() { printf '{"hook_event_name":"Stop","session_id":"%s","prompt_id":"q-%s","stop_hook_active":false,"last_assistant_message":"%s"}' "$S" "$1" "$2"; }
for tool in jq node python3 none; do
  export HOOK_PATH="$T/bin:$T/only-$tool:$T/base"
  rm -f "$DATA/tickets-$S.jsonl" "$DATA/project-$S" "$DATA/saved-$S"
  for i in 1 2 3 4; do
    hook UserPromptSubmit "" '{"hook_event_name":"UserPromptSubmit","session_id":"'$S'","prompt":"look at PAY-'$i'","prompt_id":"q-'$i'"}' > /dev/null
    hook Stop "" "$(stop_in "$i" "Done with OPS-$i.")" > /dev/null
  done
  hook Stop "" "$(stop_in 4 "Done with OPS-4.")" > /dev/null   # the same reply twice counts once
  if [ "$tool" = none ]; then
    is "tickets ($tool): nothing kept without a JSON tool" "$(cat "$DATA/tickets-$S.jsonl" 2>/dev/null)" ""
  else
    is "tickets ($tool): the last 3 messages and the last 3 replies, numbers only" \
      "$(python3 -c 'import json,sys; print(" ".join(r["r"][0] + ":" + ",".join(r["k"]) for r in map(json.loads, open(sys.argv[1]))))' "$DATA/tickets-$S.jsonl")" \
      "p:PAY-2 c:OPS-2 p:PAY-3 c:OPS-3 p:PAY-4 c:OPS-4"
  fi
  out=$(hook PreToolUse mcp__seamtrail__search_memory "$(pre mcp__seamtrail__search_memory "$S")")
  if [ "$tool" = none ]; then
    is "guard ($tool): no JSON tool → the call goes on as it is" "$out" ""
    continue
  fi
  printf '%s' "$out" | python3 -c '
import json, sys
o = json.load(sys.stdin)["hookSpecificOutput"]
assert o["hookEventName"] == "PreToolUse", o
assert o["updatedInput"] == {"query": "upi", "projectId": "p-1", "chatId": sys.argv[1],
                             "chatTickets": "OPS-2,OPS-3,OPS-4,PAY-2,PAY-3,PAY-4"}, o
' "$S" && ok "guard ($tool): chatId and chatTickets added, the call's own arguments kept" || bad "guard ($tool): '$out'"
  for name in mcp__SeamTrail__search mcp__plugin_seamtrail_seamtrail__remember; do
    printf '%s' "$(hook PreToolUse "$name" "$(pre "$name" "$S")")" | grep -Eq '"chatId": ?"'$S'"' \
      && ok "guard ($tool): $name tagged" || bad "guard ($tool): $name not tagged"
  done
  for name in mcp__github__create_issue mcp__github__seamtrail_export; do
    is "guard ($tool): another server's tool ($name) left alone" "$(hook PreToolUse "$name" "$(pre "$name" "$S")")" ""
  done
  is "guard ($tool): no session id → left alone" "$(hook PreToolUse mcp__seamtrail__remember "$(pre mcp__seamtrail__remember "")")" ""
done
unset HOOK_PATH

echo "— saved this turn (PostToolUse → saved.sh), Devin's tool_response {success, output, error}"
check() { # label, wanted (saved|not)
  if [ -f "$DATA/saved-$S" ]; then got=saved; else got=not; fi
  is "$1" "$got" "$2"
  rm -f "$DATA/saved-$S"
}
post() { # tool, tool_response JSON
  hook PostToolUse "mcp__seamtrail__$1" "$(printf '{"hook_event_name":"PostToolUse","tool_name":"mcp__seamtrail__%s","tool_input":{"question":"x","chatId":"%s"},"tool_response":%s,"session_id":"%s","prompt_id":"q-9"}' "$1" "$S" "$2" "$S")" > "$T/out"
  [ -s "$T/out" ] && bad "PostToolUse printed something: $(cat "$T/out")"
}
rm -f "$DATA/saved-$S"
for t in remember resolve settle_question widen_memory; do
  post $t '{"success":true,"output":"{\"memoryId\":\"m1\",\"kind\":\"fact\"}","error":null}'
  check "$t → saved" saved
done
post ask_seamtrail '{"success":true,"output":"{\"answer\":\"No ticket found\",\"checked\":[\"search_jira\"]}","error":null}'
check "ask_seamtrail, a question only → not saved" not
post ask_seamtrail '{"success":true,"output":"{\"answer\":\"Done: moved\",\"did\":[{\"what\":\"move ticket\",\"done\":true,\"verified\":true}]}","error":null}'
check "ask_seamtrail, a real change → saved" saved
post ask_seamtrail '{"success":true,"output":"[{\"type\":\"text\",\"text\":\"{\\\"did\\\":[{\\\"what\\\":\\\"move\\\",\\\"done\\\":true}]}\"}]","error":null}'
check "ask_seamtrail, a real change, quotes escaped twice → saved" saved
post ask_seamtrail '{"success":true,"output":"{\"answer\":\"Not done\",\"did\":[{\"what\":\"move\",\"done\":false,\"error\":\"Jira refused\"}]}","error":null}'
check "ask_seamtrail, a change that failed → not saved" not
post ask_seamtrail '{"success":true,"output":"{\"tool\":\"promotion_rules\",\"result\":{\"checklist\":[{\"label\":\"flag\",\"done\":true}]}}","error":null}'
check "ask_seamtrail, a read that happens to hold done:true → not saved" not
post undo_change '{"success":true,"output":"Undone — reading it back confirms it.","error":null}'
check "undo_change → saved" saved
post undo_change '{"success":false,"output":"","error":"That is not an undo handle"}'
check "undo_change that failed (success:false) → not saved" not
post undo_change '{"success":true,"output":"{\"isError\":true,\"content\":[{\"type\":\"text\",\"text\":\"That is not an undo handle\"}]}","error":null}'
check "undo_change that failed (MCP isError) → not saved" not
post search_memory '{"success":true,"output":"{\"results\":[]}","error":null}'
check "search_memory → not saved" not

echo "— the picked project (PostToolUse → picked.sh)"
pick() { hook PostToolUse mcp__seamtrail__set_chat_project "$(printf '{"hook_event_name":"PostToolUse","tool_name":"mcp__seamtrail__set_chat_project","tool_input":%s,"tool_response":%s,"session_id":"%s"}' "$1" "$2" "$S")"; }
pick '{"projectId":"aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee","chatId":"x"}' '{"success":true,"output":"{\"projectId\":\"aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee\",\"name\":\"Payments\"}","error":null}'
is "picked: the project kept for the turn-end check" "$(sed -n '1p' "$DATA/project-$S" 2>/dev/null)" aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee
pick '{"projectId":"99999999-bbbb-cccc-dddd-eeeeeeeeeeee"}' '{"success":false,"output":"","error":"You are not on that project"}'
is "picked: refused → unchanged" "$(sed -n '1p' "$DATA/project-$S" 2>/dev/null)" aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee
pick '{"noProject":true}' '{"success":true,"output":"No project for this chat.","error":null}'
[ -f "$DATA/project-$S" ] && bad "picked: No project kept a project" || ok "picked: No project → no project"

echo "— turn end (Stop), the same wording as the Claude Code plugin's stop.sh"
mkdir -p "$T/claude"
same_as_template() { # label — runs both stop.sh with the same project file and compares
  cp "$DATA/project-$S" "$T/claude/project-$S"
  hook Stop "" "$(stop_in 7 "Nothing to add.")" > "$T/out"
  printf '{"session_id":"%s","stop_hook_active":false}' "$S" | CLAUDE_PLUGIN_DATA="$T/claude" sh "$R/plugins/seamtrail/scripts/stop.sh" > "$T/template"
  python3 - "$T/out" "$T/template" <<'EOF' && ok "$1" || bad "$1"
import json, sys
d, t = json.load(open(sys.argv[1])), json.load(open(sys.argv[2]))
assert d["decision"] == "block" and d == t, (d, t)
EOF
}
printf 'p-1\nMy Project\n' > "$DATA/project-$S"
same_as_template "stop: asks once, names the project — word for word the Claude Code plugin's reminder"
python3 -c 'import json,sys; r=json.load(open(sys.argv[1]))["reason"]; assert "projectId p-1 (the project “My Project”)" in r and "tell your person instead" in r, r' "$T/out" || bad "stop: wording"
printf 'ask\n\n' > "$DATA/project-$S"
same_as_template "stop: two projects matched (an older SeamTrail) — same wording"
printf 'p-2\nPay "UPI" \\ Team\n' > "$DATA/project-$S"
hook Stop "" "$(stop_in 8 "Nothing.")" > "$T/out"
python3 -c 'import json,sys; r=json.load(open(sys.argv[1]))["reason"]; assert "(the project “Pay \"UPI\" \\ Team”)" in r, r' "$T/out" \
  && ok "stop: a project name with a quote and a backslash still makes valid JSON" || bad "stop: JSON with a quoted name: $(cat "$T/out")"
: > "$DATA/saved-$S"
out=$(hook Stop "" "$(stop_in 9 "Saved it.")")
if [ -z "$out" ] && [ ! -f "$DATA/saved-$S" ]; then ok "stop: saved this turn → quiet, marker cleared"; else bad "stop after a save: '$out'"; fi
is "stop: never asks twice" "$(hook Stop "" '{"hook_event_name":"Stop","session_id":"'$S'","stop_hook_active":true,"last_assistant_message":"ok"}')" ""
rm -f "$DATA/project-$S"
is "stop: no project → never asks" "$(hook Stop "" "$(stop_in 10 "Done.")")" ""
grep -q -e 'Nothing to add' -e 'Saved it' "$T/curl.log" 2>/dev/null && bad "a reply's words left the computer" || ok "the agent's replies never sent anywhere"

echo "— without Devin's data folder"
(
  unset PLUGIN_DATA
  hook PostToolUse mcp__seamtrail__remember '{"hook_event_name":"PostToolUse","tool_name":"mcp__seamtrail__remember","tool_input":{},"tool_response":{"success":true,"output":"ok","error":null},"session_id":"'$S'"}'
)
[ -f "$XDG_STATE_HOME/seamtrail/devin/saved-$S" ] && ok "no PLUGIN_DATA → \$XDG_STATE_HOME/seamtrail/devin" || bad "fallback data folder"
[ -z "$(ls -A "$HOME")" ] && ok "nothing written to the home folder" || bad "the home folder got: $(ls -A "$HOME")"

[ $fail = 0 ] && echo "ALL PASSED" || echo "SOME FAILED"
[ $fail = 0 ]
