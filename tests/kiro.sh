#!/bin/sh
# SEAM-264 · SeamTrail for Kiro: the hook scripts fed sample hook inputs in Kiro's documented format (snake_case JSON on
# stdin: hook_event_name, cwd, session_id, prompt, tool_name, tool_input, tool_response — the IDE gives tool_response as
# text, the CLI as {"success", "result"}), the hook file's matchers, the turn-end wording against the Claude Code
# template's stop.sh, and install.sh. No network: a curl stand-in answers like SeamTrail and logs every call; HOME and
# XDG_STATE_HOME are temporary folders. Run: sh tests/kiro.sh
ROOT=$(cd "$(dirname "$0")/.." && pwd)
P="$ROOT/plugins/seamtrail-kiro"
K="$P/kiro/seamtrail"
TEMPLATE="$ROOT/plugins/seamtrail/scripts/stop.sh"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
export HOME="$T/home" XDG_STATE_HOME="$T/state"
mkdir -p "$HOME" "$T/bin"
unset SEAMTRAIL_URL USER_PROMPT SEAMTRAIL_KIRO_SOURCE
DATA="$XDG_STATE_HOME/seamtrail/kiro"
S=sess_k1R0-264
PID=0f3c2a10-6b1e-4c55-9d2e-7a8b9c0d1e2f
PID2=11111111-2222-4333-8444-555555555555
fail=0
ok() { echo "ok   $1"; }
no() { echo "FAIL $1"; fail=1; }
is() { if [ "$2" = "$3" ]; then ok "$1"; else no "$1 — got [$2] wanted [$3]"; fi; }
has() { case "$2" in *"$3"*) ok "$1" ;; *) no "$1 — [$3] not in [$2]" ;; esac; }
hasnt() { case "$2" in *"$3"*) no "$1 — [$3] found" ;; *) ok "$1" ;; esac; }
file_is() { if [ -f "$2" ]; then got=yes; else got=no; fi; is "$1" "$got" "$3"; }
JSON=python3
command -v python3 >/dev/null 2>&1 || JSON=node
json_ok() { # file
  if [ "$JSON" = python3 ]; then python3 -m json.tool "$1" >/dev/null 2>&1; else node -e 'JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"))' "$1" 2>/dev/null; fi
}
jstr() { # stdin → a JSON string
  if [ "$JSON" = python3 ]; then python3 -c 'import json,sys; sys.stdout.write(json.dumps(sys.stdin.read()))'
  else node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>process.stdout.write(JSON.stringify(s)))'; fi
}

# curl stand-in: no network. Logs each call (one "--- call" block each) and answers like SeamTrail's /hook routes.
LOG="$T/curl.log"
export STUB_LOG="$LOG" STUB_ROOT="$P"
cat > "$T/bin/curl" <<'EOF'
#!/bin/sh
echo "--- call" >> "$STUB_LOG"
out=""; hdr=""; url=""
while [ $# -gt 0 ]; do
  case "$1" in
    -o) out="$2"; shift ;;
    -D) hdr="$2"; shift ;;
    -H | --max-time | --data-urlencode) printf '%s %s\n' "$1" "$2" >> "$STUB_LOG"; shift ;;
    -*) ;;
    *) url="$1"; printf 'URL %s\n' "$1" >> "$STUB_LOG" ;;
  esac
  shift
done
[ "${STUB_FAIL:-0}" = 1 ] && exit 22
case "$url" in
  */hook/start)
    printf 'HTTP/2 200\r\ncontent-type: text/plain\r\nx-seamtrail-project: %s\r\nx-seamtrail-project-name: My Project\r\n\r\n' "${STUB_PROJECT:-0f3c2a10-6b1e-4c55-9d2e-7a8b9c0d1e2f}" > "$hdr"
    printf 'SeamTrail project context for this chat.' > "$out" ;;
  */hook/message) printf 'SeamTrail news: PAY-4 moved to Done.' ;;
  https://example.invalid/plugin/*) cp "$STUB_ROOT/${url#https://example.invalid/plugin/}" "$out" 2>/dev/null || exit 22 ;;
  *) exit 6 ;;
esac
exit 0
EOF
chmod +x "$T/bin/curl"
export PATH="$T/bin:$PATH"

# A repository like a person's: a remote and a branch named after a ticket.
REPO="$T/repo"
mkdir -p "$REPO" && git -C "$REPO" init -q && git -C "$REPO" remote add origin https://github.com/acme/pay.git \
  && git -C "$REPO" checkout -q -b PAY-4-login && git -C "$REPO" -c user.name=t -c user.email=t@example.com commit -q --allow-empty -m init
REPO=$(cd "$REPO" && pwd -P)
run() { # script [arg] — in the repository, as Kiro runs a hook command (stdin = the hook's JSON); the variables
  # are handed to the script itself (an assignment before a shell function is not passed on the same way in every sh)
  (cd "$REPO" && SEAMTRAIL_TOKEN="${SEAMTRAIL_TOKEN-}" STUB_FAIL="${STUB_FAIL-}" USER_PROMPT="${USER_PROMPT-}" sh "$K/$1" $2)
}
calls() { n=$(grep -c '^--- call' "$LOG" 2>/dev/null); echo "${n:-0}"; }

echo "· files"
json_ok "$P/kiro/hooks/seamtrail.json" && ok "hooks/seamtrail.json is valid JSON" || no "hooks/seamtrail.json is not valid JSON"
json_ok "$P/kiro/settings/mcp.json" && ok "settings/mcp.json is valid JSON" || no "settings/mcp.json is not valid JSON"
if [ "$JSON" = python3 ]; then
  python3 - "$P" <<'EOF' && ok "hook file: v1, six command hooks on Kiro's triggers, each script there" || no "hook file"
import json, os, sys
p = sys.argv[1]
h = json.load(open(os.path.join(p, "kiro/hooks/seamtrail.json")))
assert h["version"] == "v1", h["version"]
trig = [x["trigger"] for x in h["hooks"]]
assert trig == ["SessionStart", "UserPromptSubmit", "PostToolUse", "PostToolUse", "PostToolUse", "Stop"], trig
for x in h["hooks"]:
    a = x["action"]
    assert a["type"] == "command" and a["command"].startswith("sh .kiro/seamtrail/"), a
    script = a["command"].split()[1].replace(".kiro/", "kiro/")
    assert os.path.isfile(os.path.join(p, script)), script
    assert x["name"].startswith("SeamTrail: ") and 0 < x["timeout"] <= 20, x
m = json.load(open(os.path.join(p, "kiro/settings/mcp.json")))
assert m == {"mcpServers": {"SeamTrail": {"url": "https://mcp.seamtrail.com/mcp", "disabled": False, "autoApprove": []}}}, m
EOF
fi
has "steering: always included" "$(sed -n '1,3p' "$P/kiro/steering/seamtrail.md")" "inclusion: always"
has "steering: the agent adds chatId itself" "$(cat "$P/kiro/steering/seamtrail.md")" "chatId: that chat id, exactly as given"
bad=""
for f in "$K/start.sh" "$K/message.sh" "$K/saved.sh" "$K/picked.sh" "$K/stop.sh" "$P/install.sh"; do sh -n "$f" || bad="$bad $f"; done
is "every script parses with sh" "$bad" ""

echo "· matchers (Kiro's tool ids: mcp_<server>_<tool>; older CLIs @<server>/<tool>)"
matchers=$(grep '"matcher"' "$P/kiro/hooks/seamtrail.json" | sed 's/.*"matcher": "\(.*\)",$/\1/')
NOTE=$(printf '%s\n' "$matchers" | sed -n 1p); CHANGE=$(printf '%s\n' "$matchers" | sed -n 2p); PICK=$(printf '%s\n' "$matchers" | sed -n 3p)
m() { # regex id → yes/no (JavaScript's RegExp, as the IDE; grep -E without node)
  if command -v node >/dev/null 2>&1; then node -e 'process.stdout.write(new RegExp(process.argv[1]).test(process.argv[2]) ? "yes" : "no")' "$1" "$2"
  elif printf '%s' "$2" | grep -Eq "$1"; then echo yes; else echo no; fi
}
for c in "NOTE mcp_seamtrail_remember yes" "NOTE @SeamTrail/remember yes" "NOTE mcp_seamtrail_widen_memory yes" \
  "NOTE mcp_seamtrail_settle_question yes" "NOTE mcp_seamtrail_resolve yes" "NOTE mcp_seamtrail_search_memory no" \
  "NOTE mcp_github_remember no" "NOTE mcp_seamtrail_ask_seamtrail no" "CHANGE mcp_seamtrail_ask_seamtrail yes" \
  "CHANGE @SeamTrail/undo_change yes" "CHANGE mcp_seamtrail_remember no" "CHANGE mcp_other_ask no" \
  "PICK mcp_seamtrail_set_chat_project yes" "PICK @SeamTrail/set_chat_project yes" "PICK mcp_seamtrail_list_projects no"; do
  set -- $c
  eval "re=\$$1"
  is "$1 matcher on $2" "$(m "$re" "$2")" "$3"
done

echo "· start.sh (SessionStart)"
START='{"hook_event_name":"SessionStart","cwd":"'"$REPO"'","session_id":"'"$S"'"}'
mkdir -p "$DATA" && : > "$DATA/saved-$S" && : > "$DATA/asked-$S"
out=$(printf '%s' "$START" | SEAMTRAIL_TOKEN=tok-1 run start.sh)
has "start: SeamTrail's text goes to the agent" "$out" "SeamTrail project context for this chat."
has "start: the agent is told the chat id" "$out" "This chat's SeamTrail chat id is $S: add chatId \"$S\" to every SeamTrail tool call"
log=$(cat "$LOG")
has "start: /hook/start" "$log" "URL https://mcp.seamtrail.com/mcp/hook/start"
has "start: assistant=kiro" "$log" "--data-urlencode assistant=kiro"
KV=$(sed -n 's/^version="\(.*\)"$/\1/p' "$P/kiro/seamtrail/start.sh")  # SEAM-273
has "start: the kit's version ($KV)" "$log" "--data-urlencode version=$KV"
has "start: chat id" "$log" "--data-urlencode chat=$S"
has "start: git remote" "$log" "--data-urlencode remote=https://github.com/acme/pay.git"
has "start: branch" "$log" "--data-urlencode branch=PAY-4-login"
has "start: folder" "$log" "--data-urlencode folder=$REPO"
has "start: the token" "$log" "-H Authorization: Bearer tok-1"
is "start: the chat's project kept" "$(cat "$DATA/project-$S" 2>/dev/null)" "$PID
My Project"
file_is "start: the chat starts clean (saved)" "$DATA/saved-$S" no
file_is "start: the chat starts clean (asked)" "$DATA/asked-$S" no
file_is "start: marks the chat started" "$DATA/started-$S" yes
: > "$LOG"; rm -f "$DATA/started-$S" "$DATA/project-$S"
out=$(printf '%s' "$START" | SEAMTRAIL_TOKEN= run start.sh)
is "start without a token: says nothing" "$out" ""
is "start without a token: calls nothing" "$(calls)" 0
file_is "start without a token: still marks the chat started" "$DATA/started-$S" yes
out=$(printf '%s' "$START" | STUB_FAIL=1 SEAMTRAIL_TOKEN=tok-1 run start.sh)
is "start, SeamTrail unreachable: silent" "$out" ""
file_is "start, SeamTrail unreachable: no project kept" "$DATA/project-$S" no
: > "$LOG"
out=$(printf '{"hook_event_name":"SessionStart","session_id":"../../x"}' | SEAMTRAIL_TOKEN=tok-1 run start.sh)
is "start, an id that is not plain: nothing at all" "$out|$(calls)" "|0"

echo "· message.sh (UserPromptSubmit)"
rm -f "$DATA/started-$S"; printf '%s' "$START" | SEAMTRAIL_TOKEN=tok-1 run start.sh >/dev/null; : > "$LOG"
: > "$DATA/asked-$S"
MSG='{"hook_event_name":"UserPromptSubmit","session_id":"'"$S"'","prompt":"Fix PAY-4 and ABC-12 (not pay-5) \"quoted\"\nthen DEF-1 secret-words-xyz","cwd":"/work/ZZZ-9-folder"}'
out=$(printf '%s' "$MSG" | SEAMTRAIL_TOKEN=tok-1 run message.sh)
is "message: SeamTrail's text goes to the agent" "$out" "SeamTrail news: PAY-4 moved to Done."
log=$(cat "$LOG")
has "message: /hook/message" "$log" "URL https://mcp.seamtrail.com/mcp/hook/message"
has "message: the chat id" "$log" "--data-urlencode chat=$S"
has "message: the message's ticket keys only (not the folder's)" "$log" "--data-urlencode tickets=ABC-12,DEF-1,PAY-4"
is "message: one call (the chat was registered at start)" "$(calls)" 1
hasnt "message: never its words" "$log" "secret-words-xyz"
file_is "message: a message from the person starts a new turn" "$DATA/asked-$S" no
: > "$LOG"; : > "$DATA/asked-$S"
REMIND='{"hook_event_name":"UserPromptSubmit","session_id":"'"$S"'","prompt":"SeamTrail: nothing was saved this turn. If in this turn your person decided something"}'
out=$(printf '%s' "$REMIND" | SEAMTRAIL_TOKEN=tok-1 run message.sh)
is "message: the turn-end reminder coming back is not the person's" "$out|$(calls)" "|0"
file_is "message: … and the turn still counts as asked" "$DATA/asked-$S" yes
out=$(printf '{"hook_event_name":"UserPromptSubmit","session_id":"%s","prompt":""}' "$S" | SEAMTRAIL_TOKEN=tok-1 run message.sh)
file_is "message: an empty prompt is not a new turn" "$DATA/asked-$S" yes
has "message: an empty prompt still gets the news" "$(cat "$LOG")" "--data-urlencode tickets="
: > "$LOG"
out=$(printf '{"hook_event_name":"UserPromptSubmit","session_id":"%s"}' "$S" | USER_PROMPT="look at PAY-7" SEAMTRAIL_TOKEN=tok-1 run message.sh)
has "message: Kiro IDE 0.x's USER_PROMPT" "$(cat "$LOG")" "--data-urlencode tickets=PAY-7"
: > "$LOG"
out=$(printf '%s' "$MSG" | SEAMTRAIL_TOKEN= run message.sh)
is "message without a token: nothing" "$out|$(calls)" "|0"
S2=sess_nostart-2
out=$(printf '{"hook_event_name":"UserPromptSubmit","cwd":"%s","session_id":"%s","prompt":"hi PAY-4"}' "$REPO" "$S2" | SEAMTRAIL_TOKEN=tok-1 run message.sh)
log=$(cat "$LOG")
has "message, no SessionStart ran: registers the chat first" "$log" "--data-urlencode chat=$S2"
has "message, no SessionStart ran: … at /hook/start" "$log" "/hook/start"
has "message, no SessionStart ran: the start text goes with the message" "$out" "SeamTrail project context for this chat."
has "message, no SessionStart ran: and the chat id" "$out" "SeamTrail chat id is $S2"
has "message, no SessionStart ran: then the news" "$out" "SeamTrail news: PAY-4 moved to Done."
is "message, no SessionStart ran: two calls" "$(calls)" 2
: > "$LOG"
printf '{"hook_event_name":"UserPromptSubmit","session_id":"%s","prompt":"again"}' "$S2" | SEAMTRAIL_TOKEN=tok-1 run message.sh >/dev/null
is "message: registers only once" "$(calls)" 1

echo "· saved.sh (PostToolUse)"
post() { # tool response-json-value mode
  printf '{"hook_event_name":"PostToolUse","cwd":"%s","session_id":"%s","tool_name":"%s","tool_input":{},"tool_response":%s}' \
    "$REPO" "$S" "$1" "$2" | run saved.sh $3
}
check() { if [ -f "$DATA/saved-$S" ]; then got=saved; else got=not; fi; is "$1" "$got" "$2"; rm -f "$DATA/saved-$S"; }
pretty() { # python dict literal → pretty JSON text (like SeamTrail's replies) → a JSON string
  python3 -c "import json; print(json.dumps($1, indent=2))" | jstr
}
rm -f "$DATA/saved-$S"
post mcp_seamtrail_remember "$(pretty '{"memoryId":"m1","kind":"fact"}')"
check "remember (IDE: the reply as text)" saved
post @SeamTrail/remember '{"success":true,"result":["{\"memoryId\":\"m1\"}"]}'
check "remember (CLI: @server/tool, success/result)" saved
post mcp_seamtrail_resolve '"ok"'; check "resolve" saved
post mcp_seamtrail_settle_question '"ok"'; check "settle_question" saved
post mcp_seamtrail_widen_memory '"ok"'; check "widen_memory" saved
post mcp_github_remember '"ok"'; check "another server's remember" not
post mcp_seamtrail_search_memory '"ok"'; check "a read (search_memory)" not
post mcp_seamtrail_ask_seamtrail "$(pretty '{"answer":"No ticket found","checked":["search_jira"]}')" change
check "ask_seamtrail, a question only" not
post mcp_seamtrail_ask_seamtrail "$(pretty '{"answer":"Done: moved","did":[{"what":"move ticket","done":True,"verified":True}]}')" change
check "ask_seamtrail, a real change (IDE text)" saved
post mcp_seamtrail_ask_seamtrail "{\"success\":true,\"result\":[$(pretty '{"did":[{"what":"move","done":True}]}')]}" change
check "ask_seamtrail, a real change (CLI success/result)" saved
post mcp_seamtrail_ask_seamtrail "$(pretty '{"answer":"Not done","did":[{"what":"move","done":False,"error":"Jira refused"}]}')" change
check "ask_seamtrail, a change that failed" not
post mcp_seamtrail_ask_seamtrail "$(pretty '{"tool":"promotion_rules","result":{"checklist":[{"label":"flag","done":True}]}}')" change
check "ask_seamtrail, a read that happens to hold done:true" not
post mcp_seamtrail_undo_change '"Undone — reading it back confirms it."' change
check "undo_change" saved
post mcp_seamtrail_undo_change '{"isError":true,"content":[{"type":"text","text":"That is not an undo handle"}]}' change
check "undo_change that failed (isError)" not
post @SeamTrail/undo_change '{"success":false,"result":["That is not an undo handle"]}' change
check "undo_change that failed (CLI success:false)" not
post mcp_seamtrail_remember '"ok"' change
check "remember sent to the change check" not

echo "· picked.sh (PostToolUse after set_chat_project)"
pick() { # tool-input-json response-json-value-or-empty [tool]
  if [ -n "$2" ]; then r=",\"tool_response\":$2"; else r=""; fi
  printf '{"hook_event_name":"PostToolUse","session_id":"%s","tool_name":"%s","tool_input":%s%s}' \
    "$S" "${3:-mcp_seamtrail_set_chat_project}" "$1" "$r" | run picked.sh
}
proj() { if [ -f "$DATA/project-$S" ]; then sed -n 1p "$DATA/project-$S"; else echo none; fi; }
rm -f "$DATA/project-$S"
# (Each answer is made first: bash 3.2 brace-expands a double-quoted literal inside "$(…)".)
r=$(pretty "{'project':{'id':'$PID2','name':'Pay'},'saved':'From now on …','next':'Call project_context with projectId $PID2 now, then answer your person.'}")
pick '{}' "$r"
is "picked: a project, from SeamTrail's answer (IDE: empty arguments)" "$(proj)" "$PID2"
is "picked: kept by its id only" "$(sed -n 2p "$DATA/project-$S")" ""
r=$(pretty "{'project':None,'saved':'From now on … private memory'}")
pick '{"none":true}' "$r"
is "picked: No project" "$(proj)" none
printf '%s\n\n' "$PID" > "$DATA/project-$S"
pick "{\"projectId\":\"$PID2\",\"none\":true}" "$(printf 'Give either projectId (the project your person picked) or none: true ("No project").' | jstr)"
is "picked: a refusal in words changes nothing" "$(proj)" "$PID"
pick "{\"projectId\":\"$PID2\"}" '{"success":false,"result":["You are not on that project"]}'
is "picked: a refusal (CLI success:false) changes nothing" "$(proj)" "$PID"
pick "{\"projectId\":\"$PID2\"}" '{"isError":true,"content":[{"type":"text","text":"no"}]}'
is "picked: a refusal (isError) changes nothing" "$(proj)" "$PID"
r=$(pretty "{'project':{'id':'$PID2','name':'Pay'}}")
pick "{\"projectId\":\"$PID2\"}" "{\"success\":true,\"result\":[$r]}"
is "picked: a project (CLI success/result)" "$(proj)" "$PID2"
printf '%s\n\n' "$PID" > "$DATA/project-$S"
pick "{\"projectId\":\"$PID2\"}" ""
is "picked: no answer in the input — the call's projectId, as in Claude Code" "$(proj)" "$PID2"
pick "{\"projectId\":\"$PID\"}" "" mcp_github_set_chat_project
is "picked: another server's tool changes nothing" "$(proj)" "$PID2"

echo "· stop.sh (Stop) — the template's words"
stop_in='{"hook_event_name":"Stop","cwd":"'"$REPO"'","session_id":"'"$S"'","assistant_response":"Done with PAY-4."}'
CC="$T/cc"; mkdir -p "$CC"
template() { printf '{"session_id":"%s","stop_hook_active":false}' "$S" | CLAUDE_PLUGIN_DATA="$CC" sh "$TEMPLATE"; }
rm -f "$DATA/saved-$S" "$DATA/asked-$S"
printf '%s\nMy Project\n' "$PID" > "$DATA/project-$S"; cp "$DATA/project-$S" "$CC/project-$S"
out=$(printf '%s' "$stop_in" | run stop.sh)
is "stop: asks once, word for word as the Claude Code plugin" "$out" "$(template)"
has "stop: names the chat's project" "$out" "projectId $PID (the project “My Project”)"
json_ok_text() { printf '%s' "$1" > "$T/out.json"; json_ok "$T/out.json"; }
json_ok_text "$out" && ok "stop: the answer is JSON Kiro reads ({\"decision\":\"block\",\"reason\":…})" || no "stop: not JSON"
out=$(printf '%s' "$stop_in" | run stop.sh)
is "stop: never asks twice (the turn end after the agent's answer)" "$out" ""
file_is "stop: … and the next turn starts over" "$DATA/asked-$S" no
: > "$DATA/saved-$S"; : > "$DATA/asked-$S"
out=$(printf '%s' "$stop_in" | run stop.sh)
is "stop: saved this turn → quiet" "$out" ""
file_is "stop: saved mark cleared" "$DATA/saved-$S" no
file_is "stop: asked mark cleared" "$DATA/asked-$S" no
out=$(printf '{"session_id":"%s","stop_hook_active":true}' "$S" | run stop.sh)
is "stop: stop_hook_active, should Kiro send it → quiet" "$out" ""
printf 'ask\n\n' > "$DATA/project-$S"; cp "$DATA/project-$S" "$CC/project-$S"
out=$(printf '%s' "$stop_in" | run stop.sh)
is "stop: two projects matched (older SeamTrail), as the template" "$out" "$(template)"
rm -f "$DATA/asked-$S"
printf '%s\n\n' "$PID2" > "$DATA/project-$S"; cp "$DATA/project-$S" "$CC/project-$S"
out=$(printf '%s' "$stop_in" | run stop.sh)
is "stop: a project picked in the chat (id only), as the template" "$out" "$(template)"
rm -f "$DATA/asked-$S" "$DATA/project-$S"
out=$(printf '%s' "$stop_in" | run stop.sh)
is "stop: no project → never asks" "$out" ""

echo "· a whole chat"
S3=sess_whole-3
: > "$LOG"
in3() { printf '{"hook_event_name":"%s","cwd":"%s","session_id":"%s"%s}' "$1" "$REPO" "$S3" "$2"; }
in3 SessionStart "" | SEAMTRAIL_TOKEN=tok-1 run start.sh >/dev/null
in3 UserPromptSubmit ',"prompt":"Let us pick the cache for PAY-4"' | SEAMTRAIL_TOKEN=tok-1 run message.sh >/dev/null
r1=$(in3 Stop "" | run stop.sh)
has "turn 1: nothing saved → the reminder" "$r1" '"decision":"block"'
in3 UserPromptSubmit ',"prompt":"SeamTrail: nothing was saved this turn. If in this turn …"' | SEAMTRAIL_TOKEN=tok-1 run message.sh >/dev/null
r2=$(in3 Stop "" | run stop.sh)
is "turn 1: the agent answered the reminder → quiet (no loop)" "$r2" ""
in3 UserPromptSubmit ',"prompt":"We chose Redis because of TTLs"' | SEAMTRAIL_TOKEN=tok-1 run message.sh >/dev/null
in3 PostToolUse ',"tool_name":"mcp_seamtrail_remember","tool_input":{},"tool_response":"{}"' | run saved.sh
r3=$(in3 Stop "" | run stop.sh)
is "turn 2: the agent saved → quiet" "$r3" ""
in3 UserPromptSubmit ',"prompt":"ok next"' | SEAMTRAIL_TOKEN=tok-1 run message.sh >/dev/null
r4=$(in3 Stop "" | run stop.sh)
has "turn 3: nothing saved → the reminder again" "$r4" '"decision":"block"'
hasnt "no message text ever left the computer" "$(cat "$LOG")" "Redis"

echo "· install.sh"
W="$T/team-repo"; mkdir -p "$W"
inst() { (cd "$1" && shift && sh "$P/install.sh" "$@") >"$T/install.out" 2>&1; }
inst "$W" && ok "install: runs from a checkout" || no "install failed: $(cat "$T/install.out")"
for f in hooks/seamtrail.json steering/seamtrail.md settings/mcp.json; do
  cmp -s "$W/.kiro/$f" "$P/kiro/$f" && ok "install: .kiro/$f" || no "install: .kiro/$f differs"
done
for f in start message saved picked stop; do
  cmp -s "$W/.kiro/seamtrail/$f.sh" "$K/$f.sh" && [ -x "$W/.kiro/seamtrail/$f.sh" ] || no "install: .kiro/seamtrail/$f.sh"
done
ok "install: the five scripts, executable"
has "install: says to commit" "$(cat "$T/install.out")" "git add .kiro/hooks/seamtrail.json"
has "install: says where the token comes from" "$(cat "$T/install.out")" "Settings → Agents · MCP connector → Token"
cp "$W/.kiro/settings/mcp.json" "$T/before.json"
inst "$W" && cmp -s "$W/.kiro/settings/mcp.json" "$T/before.json" && ok "install again: mcp.json left as it is" || no "install again changed mcp.json"
has "install again: says so" "$(cat "$T/install.out")" "already has SeamTrail: left as it is"
W2="$T/repo-with-servers"; mkdir -p "$W2/.kiro/settings"
printf '{\n  "mcpServers": {\n    "github": { "url": "https://api.githubcopilot.com/mcp/", "disabled": false }\n  },\n  "other": 1\n}\n' > "$W2/.kiro/settings/mcp.json"
if inst "$W2"; then
  if [ "$JSON" = python3 ]; then
    python3 - "$W2/.kiro/settings/mcp.json" <<'EOF' && ok "install: SeamTrail added beside the other servers, the rest as it was" || no "install merge"
import json, sys
d = json.load(open(sys.argv[1]))
assert d["other"] == 1, d
assert d["mcpServers"]["github"] == {"url": "https://api.githubcopilot.com/mcp/", "disabled": False}, d
assert d["mcpServers"]["SeamTrail"] == {"url": "https://mcp.seamtrail.com/mcp", "disabled": False, "autoApprove": []}, d
EOF
  fi
else no "install into a repo with servers: $(cat "$T/install.out")"; fi
W3="$T/repo-own-seamtrail"; mkdir -p "$W3/.kiro/settings"
printf '{ "mcpServers": { "seamtrail-prod": { "url": "https://mcp.seamtrail.com/mcp" } } }\n' > "$W3/.kiro/settings/mcp.json"
cp "$W3/.kiro/settings/mcp.json" "$T/own.json"
inst "$W3" && cmp -s "$W3/.kiro/settings/mcp.json" "$T/own.json" && ok "install: a SeamTrail server already there is left alone" || no "install touched an existing SeamTrail server"
W4="$T/repo-remote"; mkdir -p "$W4"
(cd "$W4" && SEAMTRAIL_KIRO_SOURCE=https://example.invalid/plugin sh "$P/install.sh") >"$T/install.out" 2>&1 \
  && cmp -s "$W4/.kiro/hooks/seamtrail.json" "$P/kiro/hooks/seamtrail.json" && cmp -s "$W4/.kiro/seamtrail/stop.sh" "$K/stop.sh" \
  && ok "install: from GitHub (curl … | sh)" || no "install from a URL: $(cat "$T/install.out")"
W5="$T/repo-down"; mkdir -p "$W5"
(cd "$W5" && SEAMTRAIL_KIRO_SOURCE=https://example.invalid/nothing sh "$P/install.sh") >"$T/install.out" 2>&1
[ $? -ne 0 ] && [ ! -d "$W5/.kiro" ] && ok "install: when the files cannot be fetched, nothing is written" || no "install wrote something after a failed fetch"
W6="$T/repo-url"; mkdir -p "$W6"
(cd "$W6" && SEAMTRAIL_URL=https://mcp.example.com/mcp sh "$P/install.sh") >/dev/null 2>&1
has "install: a company's own SeamTrail address" "$(cat "$W6/.kiro/settings/mcp.json")" '"url": "https://mcp.example.com/mcp"'
(cd "$W6" && SEAMTRAIL_URL='https://x/"y' sh "$P/install.sh") >/dev/null 2>&1 && no "install took an address with a quote" || ok "install: refuses an address with a quote"
(cd "$HOME" && sh "$P/install.sh") >/dev/null 2>&1 && no "install ran in the home folder" || ok "install: refuses the home folder without --user"
inst "$HOME" --user && ok "install --user: runs" || no "install --user: $(cat "$T/install.out")"
has "install --user: hooks call the scripts by full path" "$(cat "$HOME/.kiro/hooks/seamtrail.json")" "\"sh $HOME/.kiro/seamtrail/start.sh\""
hasnt "install --user: no workspace path left" "$(cat "$HOME/.kiro/hooks/seamtrail.json")" "sh .kiro/"
has "install --user: no commit step" "$(cat "$T/install.out")" "1. The hooks work as you"
inst "$W" && has "install in a repo with --user hooks too: warns they would run twice" "$(cat "$T/install.out")" "Kiro would run both"
# The installed hooks, run as Kiro runs them: the command line from the hook file, in the repository's folder.
: > "$LOG"
cmd=$(grep '"command"' "$W/.kiro/hooks/seamtrail.json" | sed -n 1p | sed 's/.*"command": "\([^"]*\)".*/\1/')
out=$(printf '{"hook_event_name":"SessionStart","session_id":"sess_inst-6"}' | (cd "$W" && SEAMTRAIL_TOKEN=tok-1 sh -c "$cmd"))
has "installed hook command runs: $cmd" "$out" "SeamTrail chat id is sess_inst-6"
cmd=$(grep '"command"' "$HOME/.kiro/hooks/seamtrail.json" | sed -n 6p | sed 's/.*"command": "\([^"]*\)".*/\1/')
out=$(printf '{"hook_event_name":"Stop","session_id":"sess_inst-6"}' | (cd "$T" && sh -c "$cmd"); echo "exit $?")
has "--user turn-end hook runs from any folder: $cmd" "$out" "exit 0"
has "--user turn-end hook: asks into the chat's project" "$out" '"decision":"block"'

[ $fail = 0 ] && echo "ALL PASSED" || echo "SOME FAILED"
exit $fail
