#!/bin/sh
# SEAM-253 · the SeamTrail extension for Gemini CLI: its hook scripts fed sample inputs in Gemini CLI's hook format
# (geminicli.com/docs/hooks/reference), with a stand-in curl — no SeamTrail server is called, and nothing outside a
# temporary folder is touched. Needs python3 (checks) and node (matchers).
# Run: sh tests/gemini.sh        Under dash as well: TEST_SH=dash sh tests/gemini.sh
ROOT=$(cd "$(dirname "$0")/.." && pwd)
P="$ROOT/plugins/seamtrail-gemini"
TEMPLATE="$ROOT/plugins/seamtrail"
SH=$(command -v "${TEST_SH:-sh}")
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
unset SEAMTRAIL_TOKEN SEAMTRAIL_URL GEMINI_SESSION_ID CLAUDE_PLUGIN_DATA
export XDG_STATE_HOME="$W/state"
DATA="$XDG_STATE_HOME/seamtrail/gemini"
S=0b7c5a8e-1f2d-4c3b-9a8e-7d6c5b4a3f21
PROJ=7f3e2a10-4b5c-4d6e-8f90-a1b2c3d4e5f6
fail=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }

# A stand-in curl: logs its arguments, answers with $FAKE/body and $FAKE/headers, or fails when $FAKE/fail exists.
FAKE="$W/fake"
mkdir -p "$W/bin" "$FAKE"
cat > "$W/bin/curl" <<'EOF'
#!/bin/sh
for a in "$@"; do printf '%s\n' "$a"; done >> "$FAKE/curl.log"
[ -f "$FAKE/fail" ] && exit 22
out=""; hdr=""
while [ $# -gt 0 ]; do
  case "$1" in -o) out="$2"; shift ;; -D) hdr="$2"; shift ;; esac
  shift
done
if [ -n "$hdr" ]; then
  if [ -f "$FAKE/headers" ]; then cat "$FAKE/headers"; else printf 'HTTP/1.1 200 OK\r\n\r\n'; fi > "$hdr"
fi
if [ -n "$out" ]; then cat "$FAKE/body" > "$out" 2>/dev/null || : > "$out"; else cat "$FAKE/body" 2>/dev/null; fi
exit 0
EOF
chmod +x "$W/bin/curl"
export PATH="$W/bin:$PATH" FAKE
fresh() { rm -f "$FAKE/curl.log" "$FAKE/fail" "$FAKE/headers" "$FAKE/body"; } # a new call, nothing answered yet
called() { [ -f "$FAKE/curl.log" ] && grep -qxF -- "$1" "$FAKE/curl.log"; }  # the last calls had this argument

# A repository to start in, with a remote and a ticket branch.
REPO="$W/repo"
git init -q "$REPO" && git -C "$REPO" checkout -q -b SEAM-253-gemini
git -C "$REPO" -c user.email=t@example.com -c user.name=t commit -q --allow-empty -m init
git -C "$REPO" remote add origin https://github.com/acme/app.git
export GEMINI_PROJECT_DIR="$REPO"

# Hook inputs as Gemini CLI writes them (JSON.stringify: one line, Gemini CLI's own fields first).
base() {
  printf '"session_id":"%s","transcript_path":"%s/chats/session.json","cwd":"%s","hook_event_name":"%s","timestamp":"2026-10-22T10:00:00.000Z"' \
    "${SID:-$S}" "$W" "$REPO" "$1"
}
session_start() { printf '{%s,"source":"%s"}' "$(base SessionStart)" "$1"; }
pre_compress() { printf '{%s,"trigger":"auto"}' "$(base PreCompress)"; }
before_agent() { printf '{%s,"prompt":"%s"}' "$(base BeforeAgent)" "$1"; }           # $1: JSON-escaped text
after_agent() { printf '{%s,"prompt":"%s","prompt_response":"%s","stop_hook_active":%s}' "$(base AfterAgent)" "$1" "$2" "$3"; }
before_tool() { # tool, tool_input JSON, server
  printf '{%s,"tool_name":"%s","tool_input":%s,"mcp_context":{"server_name":"%s","tool_name":"%s","url":"https://mcp.seamtrail.com/mcp"}}' \
    "$(base BeforeTool)" "$1" "$2" "$3" "${1##*_}"
}
after_tool() { # tool, tool_input JSON, tool_response JSON
  printf '{%s,"tool_name":"%s","tool_input":%s,"tool_response":%s,"mcp_context":{"server_name":"seamtrail","tool_name":"%s","url":"https://mcp.seamtrail.com/mcp"}}' \
    "$(base AfterTool)" "$1" "$2" "$3" "${1#mcp_seamtrail_}"
}
run() { script="$1"; shift; "$SH" "$P/scripts/$script" "$@"; }

# check_json label json python-expression [args…]: the expression over d (the parsed JSON) and a (the args) is true.
check_json() {
  label="$1"; json="$2"; expr="$3"; shift 3
  if printf '%s' "$json" | python3 -c '
import json, sys
d = json.load(sys.stdin)
a = sys.argv[2:]
sys.exit(0 if eval(sys.argv[1]) else 1)' "$expr" "$@" 2>/dev/null; then ok "$label"; else bad "$label → $json"; fi
}
quiet() { if [ -z "$2" ]; then ok "$1"; else bad "$1 → printed: $2"; fi; }

echo "· manifest and hooks"
python3 -m json.tool "$P/gemini-extension.json" > /dev/null && python3 -m json.tool "$P/hooks/hooks.json" > /dev/null \
  && ok "gemini-extension.json and hooks/hooks.json are valid JSON" || bad "invalid JSON"
check_json "manifest: name, version, SeamTrail's server over streamable HTTP with the token header, the token asked as a secret" \
  "$(cat "$P/gemini-extension.json")" \
  'd["name"] == "seamtrail" and d["version"] and d["mcpServers"]["seamtrail"]["httpUrl"] == "https://mcp.seamtrail.com/mcp" and d["mcpServers"]["seamtrail"]["headers"]["Authorization"] == "Bearer $SEAMTRAIL_TOKEN" and d["settings"] == [dict(d["settings"][0], envVar="SEAMTRAIL_TOKEN", sensitive=True)] and "hooks" not in d'
check_json "hooks.json: Gemini CLI events only, command hooks with a timeout in ms, every script there" \
  "$(cat "$P/hooks/hooks.json")" \
  'set(d["hooks"]) <= {"BeforeTool","AfterTool","BeforeAgent","AfterAgent","SessionStart","SessionEnd","PreCompress","BeforeModel","AfterModel","BeforeToolSelection","Notification"} and all(h["type"] == "command" and 1000 <= h["timeout"] <= 60000 and __import__("os").path.isfile(h["command"].split("\"")[1].replace("${extensionPath}", a[0])) for e in d["hooks"].values() for g in e for h in g["hooks"])' "$P"
# Gemini CLI tests a tool event's matcher as a JavaScript RegExp against the tool name (mcp_<server>_<tool>).
if node -e '
const hooks = require(process.argv[1]).hooks;
// arg: undefined = any, "" = the script with no argument, else the argument it is called with.
const has = (h, script, arg) => h.command.includes(script) && (arg === undefined || (arg ? h.command.endsWith(" " + arg) : h.command.endsWith("\"")));
const m = (event, script, arg) => hooks[event].filter((g) => g.hooks.some((h) => has(h, script, arg))).map((g) => new RegExp(g.matcher));
const hit = (rs, name) => rs.some((r) => r.test(name));
const T = (s) => "mcp_seamtrail_" + s;
const cases = [
  [m("BeforeTool", "guard.sh"), [T("remember"), T("search_memory"), "mcp_github_create_issue"], ["read_file", "run_shell_command", "write_file"]],
  [m("AfterTool", "saved.sh", ""), [T("remember"), T("resolve"), T("settle_question"), T("widen_memory"), "mcp_SeamTrail_remember"], [T("search_memory"), T("ask_seamtrail"), T("set_chat_project"), T("project_context"), "remember"]],
  [m("AfterTool", "saved.sh", "change"), [T("ask_seamtrail"), T("undo_change")], [T("remember"), T("ticket_details"), "undo_change"]],
  [m("AfterTool", "picked.sh"), [T("set_chat_project")], [T("get_project"), T("list_projects"), "set_chat_project", T("set_chat_project_v2")]],
];
for (const [rs, yes, no] of cases) {
  if (!rs.length) throw new Error("no matcher");
  for (const n of yes) if (!hit(rs, n)) throw new Error("should match " + n);
  for (const n of no) if (hit(rs, n)) throw new Error("should not match " + n);
}' "$P/hooks/hooks.json"; then ok "matchers pick SeamTrail's tools as Gemini CLI names them"; else bad "matchers"; fi

echo "· start.sh (SessionStart, PreCompress)"
fresh
# The server's text, with what JSON must escape: quotes, a backslash, a tab, a Windows line end, a control character.
printf 'Project “Pay Core” — say "hi" to C:\\temp\there\r\n<b>%%s</b> 100%%\001\nlast line' > "$FAKE/body"
printf 'HTTP/1.1 200 OK\r\nx-seamtrail-project: %s\r\nX-SeamTrail-Project-Name: Pay "Core"\r\n\r\n' "$PROJ" > "$FAKE/headers"
mkdir -p "$DATA" && : > "$DATA/saved-$S" && : > "$DATA/remind-$S"
out=$(session_start startup | SEAMTRAIL_TOKEN=tok-1 run start.sh)
check_json "chat start: SeamTrail's text goes to Gemini as context, escaped right" "$out" \
  'd == {"hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": a[0]}}' \
  "$(printf 'Project “Pay Core” — say "hi" to C:\\temp\there\n<b>%%s</b> 100%%\nlast line')"
V=$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' "$P/gemini-extension.json")  # SEAM-273
if called "https://mcp.seamtrail.com/mcp/hook/start" && called "assistant=gemini" && called "chat=$S" && called "folder=$REPO" \
  && called "remote=https://github.com/acme/app.git" && called "branch=SEAM-253-gemini" && called "Authorization: Bearer tok-1" \
  && called "version=$V"; then
  ok "chat start: registers the chat (assistant=gemini, chat id, folder, remote, branch, the extension's version $V) on the token"
else bad "chat start call: $(tr '\n' ' ' < "$FAKE/curl.log")"; fi
if grep -Eq 'chatName|transcript|session\.json' "$FAKE/curl.log"; then bad "chat start sent more than it should"; else ok "chat start: sends nothing else (no transcript, no chat text)"; fi
if [ "$(cat "$DATA/project-$S")" = "$(printf '%s\nPay "Core"' "$PROJ")" ]; then ok "chat start: keeps the chat's project and name"; else bad "project file: $(cat "$DATA/project-$S")"; fi
if [ ! -f "$DATA/saved-$S" ] && [ ! -f "$DATA/remind-$S" ]; then ok "chat start: the chat starts clean (not saved, no reminder waiting)"; else bad "markers left at chat start"; fi

fresh; printf 'Resumed context' > "$FAKE/body"
out=$(session_start resume | SEAMTRAIL_TOKEN=tok-1 run start.sh)
check_json "resumed chat: context again" "$out" 'd["hookSpecificOutput"]["additionalContext"] == "Resumed context"'

fresh; printf 'Context after clear' > "$FAKE/body"
out=$(session_start clear | SEAMTRAIL_TOKEN=tok-1 run start.sh)
quiet "after /clear: nothing printed (Gemini CLI drops it there)" "$out"
if [ "$(cat "$DATA/start-$S")" = "Context after clear" ]; then ok "after /clear: kept for the first message"; else bad "after /clear: not kept"; fi
fresh; printf 'News since you looked' > "$FAKE/body"
out=$(before_agent 'hello' | SEAMTRAIL_TOKEN=tok-1 run message.sh)
check_json "after /clear: the first message hands over the start context, then the news" "$out" \
  'd == {"hookSpecificOutput": {"hookEventName": "BeforeAgent", "additionalContext": "Context after clear\n\nNews since you looked"}}'
if [ ! -f "$DATA/start-$S" ]; then ok "after /clear: handed over once"; else bad "start context kept after use"; fi

fresh; printf 'Context after compressing' > "$FAKE/body"; : > "$DATA/saved-$S"
out=$(pre_compress | SEAMTRAIL_TOKEN=tok-1 run start.sh)
quiet "compressing: nothing printed" "$out"
if [ "$(cat "$DATA/start-$S")" = "Context after compressing" ] && [ -f "$DATA/saved-$S" ] && called "chat=$S"; then
  ok "compressing: start context fetched again for the next message; the turn's saved mark kept"
else bad "compressing"; fi
rm -f "$DATA/start-$S" "$DATA/saved-$S"

fresh; printf 'x' > "$FAKE/body"; : > "$DATA/saved-$S"
: > "$DATA/project-old-chat"; touch -t 200001010000 "$DATA/project-old-chat"; : > "$DATA/project-recent-chat"
out=$(session_start startup | run start.sh)
if [ -z "$out" ] && [ ! -f "$FAKE/curl.log" ] && [ ! -f "$DATA/saved-$S" ]; then ok "no token: silent, no call, still starts clean"; else bad "no token"; fi
if [ ! -f "$DATA/project-old-chat" ] && [ -f "$DATA/project-recent-chat" ]; then ok "chat start: what this computer kept goes after a month"; else bad "old state not pruned"; fi
rm -f "$DATA/project-recent-chat"

fresh; : > "$FAKE/fail"
out=$(session_start startup | SEAMTRAIL_TOKEN=tok-1 run start.sh)
if [ -z "$out" ] && [ ! -f "$DATA/project-$S" ]; then ok "server unreachable: silent"; else bad "server failure: $out"; fi

fresh; : > "$FAKE/body"
out=$(session_start startup | SEAMTRAIL_TOKEN=tok-1 run start.sh)
quiet "nothing to say: nothing printed" "$out"

fresh; printf 'x' > "$FAKE/body"
out=$(session_start startup | SEAMTRAIL_TOKEN=tok-1 SEAMTRAIL_URL=https://st.example.com/mcp/ run start.sh)
if called "https://st.example.com/mcp/hook/start"; then ok "SEAMTRAIL_URL: a company's own SeamTrail"; else bad "SEAMTRAIL_URL"; fi

echo "· message.sh (BeforeAgent)"
fresh; printf 'PAY-4: decided by Priya' > "$FAKE/body"; : > "$DATA/saved-$S"
out=$(before_agent 'Look at PAY-4 and ABC-12\nthen pay-5, X-1, utf-8 and PAY-4 again' | SEAMTRAIL_TOKEN=tok-1 run message.sh)
check_json "message: SeamTrail's answer goes to Gemini with the message" "$out" \
  'd == {"hookSpecificOutput": {"hookEventName": "BeforeAgent", "additionalContext": "PAY-4: decided by Priya"}}'
if called "https://mcp.seamtrail.com/mcp/hook/message" && called "chat=$S" && called "tickets=ABC-12,PAY-4"; then
  ok "message: sends the chat id and the ticket numbers only"
else bad "message call: $(tr '\n' ' ' < "$FAKE/curl.log")"; fi
if grep -q 'Look at' "$FAKE/curl.log"; then bad "message: words sent"; else ok "message: never the words"; fi
if [ ! -f "$DATA/saved-$S" ]; then ok "message: a new turn (not saved)"; else bad "message: saved marker left"; fi
fresh; printf 'x' > "$FAKE/body"
before_agent 'AA-11 BB-22 CC-33 DD-44 EE-55 FF-66' | SEAMTRAIL_TOKEN=tok-1 run message.sh > /dev/null
if called "tickets=AA-11,BB-22,CC-33,DD-44,EE-55"; then ok "message: at most five ticket numbers"; else bad "five tickets: $(grep tickets= "$FAKE/curl.log")"; fi
fresh; : > "$FAKE/body"
out=$(before_agent 'nothing new' | SEAMTRAIL_TOKEN=tok-1 run message.sh)
quiet "message: nothing to tell, nothing added" "$out"
fresh; : > "$DATA/saved-$S"
out=$(before_agent 'hello PAY-4' | run message.sh)
if [ -z "$out" ] && [ ! -f "$FAKE/curl.log" ] && [ ! -f "$DATA/saved-$S" ]; then ok "message, no token: silent, no call, still a new turn"; else bad "message without token"; fi

echo "· tickets.sh (BeforeAgent person, AfterAgent agent)"
rm -f "$DATA"/tickets-*
for m in 'one PAY-1' 'two PAY-2' 'three PAY-3' 'four PAY-4 and ABC-12'; do before_agent "$m" | run tickets.sh person; done
after_agent 'four' 'Done with OPS-9' false | run tickets.sh agent
after_agent 'four' 'Done with OPS-9' false | run tickets.sh agent
TICKETS_JQ=$(cat "$DATA/tickets-$S.jsonl")
check_json "tickets: the last 3 messages each way, numbers only, the same reply once" \
  "[$(printf '%s' "$TICKETS_JQ" | paste -sd, -)]" \
  '[(x["r"], x["k"]) for x in d] == [("person", ["PAY-2"]), ("person", ["PAY-3"]), ("person", ["ABC-12", "PAY-4"]), ("agent", ["OPS-9"])] and all(set(x) == {"r", "n", "k"} for x in d)'
# The same without jq (node), and without jq and node (python3).
mkdir -p "$W/nojq" "$W/py" "$W/none"
for t in cat grep head tail sed tr find mkdir rm mv cp dirname uname sort paste xcode-select; do
  p=$(command -v "$t") && for d in nojq py none; do ln -sf "$p" "$W/$d/$t"; done
done
ln -sf "$(command -v node)" "$W/nojq/node"
ln -sf "$(command -v python3)" "$W/py/python3"
for d in nojq py; do
  rm -f "$DATA"/tickets-*
  for m in 'one PAY-1' 'two PAY-2' 'three PAY-3' 'four PAY-4 and ABC-12'; do before_agent "$m" | PATH="$W/$d" "$SH" "$P/scripts/tickets.sh" person; done
  after_agent 'four' 'Done with OPS-9' false | PATH="$W/$d" "$SH" "$P/scripts/tickets.sh" agent
  after_agent 'four' 'Done with OPS-9' false | PATH="$W/$d" "$SH" "$P/scripts/tickets.sh" agent
  got=$(python3 -c 'import json,sys; print([(x["r"], x["k"]) for x in map(json.loads, open(sys.argv[1]))])' "$DATA/tickets-$S.jsonl" 2>&1)
  want=$(python3 -c 'import json,sys; print([(x["r"], x["k"]) for x in map(json.loads, sys.stdin)])' <<EOF
$TICKETS_JQ
EOF
)
  if [ "$got" = "$want" ]; then ok "tickets without jq ($([ $d = nojq ] && echo node || echo python3)): the same"; else bad "tickets via $d: $got"; fi
done

echo "· guard.sh (BeforeTool)"
out=$(before_tool mcp_seamtrail_search_memory '{"query":"pricing","workingOn":"Pricing page"}' seamtrail | run guard.sh)
check_json "guard: the chat id and its ticket numbers go into a SeamTrail call (Gemini CLI merges them)" "$out" \
  'd == {"hookSpecificOutput": {"hookEventName": "BeforeTool", "tool_input": {"chatId": a[0], "chatTickets": "ABC-12,OPS-9,PAY-2,PAY-3,PAY-4"}}}' "$S"
out=$(before_tool mcp_SeamTrail_remember '{"content":"x"}' SeamTrail | run guard.sh)
check_json "guard: a SeamTrail server the person added themselves" "$out" 'd["hookSpecificOutput"]["tool_input"]["chatId"] == a[0]' "$S"
rm -f "$DATA"/tickets-*
out=$(before_tool mcp_seamtrail_remember '{"content":"x"}' seamtrail | run guard.sh)
check_json "guard: no ticket numbers kept → the chat id only" "$out" 'd["hookSpecificOutput"]["tool_input"] == {"chatId": a[0]}' "$S"
out=$(before_tool mcp_github_create_issue '{"title":"x","server_name":"seamtrail"}' github | run guard.sh)
quiet "guard: another server's tool is never touched" "$out"
out=$(SID='bad id/../x'; before_tool mcp_seamtrail_remember '{"content":"x"}' seamtrail | run guard.sh)
quiet "guard: a session id that is not an id is never sent" "$out"
out=$(before_tool mcp_seamtrail_remember '{"content":"x"}' seamtrail | PATH="$W/none" "$SH" "$P/scripts/guard.sh")
check_json "guard: works with no JSON tool on the computer" "$out" 'd["hookSpecificOutput"]["tool_input"] == {"chatId": a[0]}' "$S"

echo "· saved.sh (AfterTool)"
saved() { # label, tool, tool_response JSON, mode, wanted (saved|not)
  rm -f "$DATA/saved-$S"
  after_tool "$2" '{"question":"x","chatId":"'"$S"'"}' "$3" | run saved.sh $4
  if [ -f "$DATA/saved-$S" ]; then got=saved; else got=not; fi
  if [ "$got" = "$5" ]; then ok "saved: $1 → $got"; else bad "saved: $1 → $got (wanted $5)"; fi
}
wrap() { printf '{"llmContent":[{"text":"<untrusted_context>\\n%s\\n</untrusted_context>"}],"returnDisplay":"%s"}' "$1" "$1"; }
saved "remember" mcp_seamtrail_remember "$(wrap '{\"memoryId\":\"m1\",\"kind\":\"fact\"}')" "" saved
saved "resolve" mcp_seamtrail_resolve "$(wrap 'Resolved.')" "" saved
saved "another server's resolve" mcp_github_resolve "$(wrap 'Resolved.')" "" not
saved "ask_seamtrail, a question only" mcp_seamtrail_ask_seamtrail "$(wrap '{\"answer\":\"No ticket found\",\"checked\":[\"search_jira\"]}')" change not
saved "ask_seamtrail, a real change" mcp_seamtrail_ask_seamtrail "$(wrap '{\"answer\":\"Done: moved\",\"did\":[{\"what\":\"move ticket\",\"done\":true,\"verified\":true}]}')" change saved
saved "ask_seamtrail, a change that failed" mcp_seamtrail_ask_seamtrail "$(wrap '{\"answer\":\"Not done\",\"did\":[{\"what\":\"move\",\"done\":false,\"error\":\"Jira refused\"}]}')" change not
saved "ask_seamtrail, a read that happens to hold done:true" mcp_seamtrail_ask_seamtrail "$(wrap '{\"tool\":\"promotion_rules\",\"result\":{\"checklist\":[{\"label\":\"flag\",\"done\":true}]}}')" change not
saved "undo_change" mcp_seamtrail_undo_change "$(wrap 'Undone — reading it back confirms it.')" change saved
saved "undo_change that failed" mcp_seamtrail_undo_change \
  '{"llmContent":"MCP tool undo_change reported tool error for function call: {\"name\":\"undo_change\"} with response: [{\"isError\":true,\"content\":[{\"type\":\"text\",\"text\":\"That is not an undo handle\"}]}]","returnDisplay":"Error: MCP tool '"'"'undo_change'"'"' reported an error.","error":{"message":"That is not an undo handle","type":"mcp_tool_error"}}' change not

echo "· picked.sh (AfterTool set_chat_project)"
rm -f "$DATA/project-$S"
after_tool mcp_seamtrail_set_chat_project '{"projectId":"'"$PROJ"'","chatId":"'"$S"'"}' "$(wrap '{\"projectId\":\"00000000-0000-0000-0000-000000000000\",\"name\":\"Pay\"}')" | run picked.sh
if [ "$(cat "$DATA/project-$S" 2>/dev/null)" = "$PROJ" ]; then ok "picked: the chat's project, from the call itself"; else bad "picked: $(cat "$DATA/project-$S" 2>/dev/null)"; fi
after_tool mcp_seamtrail_set_chat_project '{"projectId":"11111111-2222-3333-4444-555555555555"}' '{"llmContent":"x","returnDisplay":"Error","error":{"message":"not on that project","type":"mcp_tool_error"}}' | run picked.sh
if [ "$(cat "$DATA/project-$S")" = "$PROJ" ]; then ok "picked: refused → unchanged"; else bad "picked after a refusal"; fi
after_tool mcp_seamtrail_set_chat_project '{"none":true}' "$(wrap 'No project for this chat.')" | run picked.sh
if [ ! -f "$DATA/project-$S" ]; then ok "picked: \"No project\" → no reminder"; else bad "picked none"; fi

echo "· stop.sh (AfterAgent) never stops the agent; remind.sh has the Claude Code plugin's words"
CLAUDE_DATA="$W/claude"; mkdir -p "$CLAUDE_DATA"
template() { : > "$CLAUDE_DATA/remind-$S"; printf '{"session_id":"%s"}' "$S" | CLAUDE_PLUGIN_DATA="$CLAUDE_DATA" sh "$TEMPLATE/scripts/remind.sh"; }
printf '%s\nMy Project\n' "$PROJ" > "$DATA/project-$S"; printf '%s\nMy Project\n' "$PROJ" > "$CLAUDE_DATA/project-$S"
out=$(after_agent 'Ship it' 'Shipped.' false | run stop.sh)
quiet "stop: nothing saved → never stops Gemini CLI" "$out"
note=$(run remind.sh "$DATA" "$S")
if [ -n "$note" ] && [ "$note" = "$(template)" ]; then ok "remind: the same words as the Claude Code plugin"; else bad "remind words: [$note]"; fi
case "$note" in *"projectId $PROJ (the project “My Project”)"*) ok "remind: names the project" ;; *) bad "remind: no project in [$note]" ;; esac
quiet "remind: once only" "$(run remind.sh "$DATA" "$S")"
: > "$DATA/saved-$S"; : > "$DATA/remind-$S"
out=$(after_agent 'Ship it' 'Shipped.' false | run stop.sh)
if [ -z "$out" ] && [ ! -f "$DATA/saved-$S" ] && [ ! -f "$DATA/remind-$S" ]; then ok "stop: saved this turn → quiet, marks cleared"; else bad "stop after a save: $out"; fi
printf 'ask\n\n' > "$DATA/project-$S"; printf 'ask\n\n' > "$CLAUDE_DATA/project-$S"
after_agent 'x' 'y' false | run stop.sh > /dev/null
if [ "$(run remind.sh "$DATA" "$S")" = "$(template)" ]; then ok "remind: two projects matched (older SeamTrail) — the same words"; else bad "remind for two projects"; fi
printf '%s\nPay \\"Core\\" \\u00b7\n' "$PROJ" > "$DATA/project-$S"
after_agent 'x' 'y' false | run stop.sh > /dev/null
case "$(run remind.sh "$DATA" "$S")" in *"with projectId $PROJ: one note"*) ok "remind: an escaped name never shows its codes: the id alone" ;; *) bad "remind, escaped name" ;; esac
rm -f "$DATA/project-$S"
out=$(after_agent 'x' 'y' false | run stop.sh)
if [ -z "$out" ] && [ ! -f "$DATA/remind-$S" ]; then ok "stop: no project → never reminds"; else bad "stop without a project: $out"; fi

echo "· a whole turn"
fresh; printf 'Project context' > "$FAKE/body"
printf 'HTTP/1.1 200 OK\r\nx-seamtrail-project: %s\r\nx-seamtrail-project-name: Pay\r\n\r\n' "$PROJ" > "$FAKE/headers"
session_start startup | SEAMTRAIL_TOKEN=tok-1 run start.sh > /dev/null
fresh
before_agent 'We picked Stripe for PAY-4' | run tickets.sh person
before_agent 'We picked Stripe for PAY-4' | SEAMTRAIL_TOKEN=tok-1 run message.sh > /dev/null
out=$(after_agent 'We picked Stripe for PAY-4' 'Noted.' false | run stop.sh)
quiet "turn: nothing saved → Gemini CLI is not stopped" "$out"
fresh; printf 'PAY-4: news' > "$FAKE/body"
out=$(before_agent 'Next question' | SEAMTRAIL_TOKEN=tok-1 run message.sh)
check_json "turn: the next message brings the news and one reminder, as valid JSON" "$out" \
  'd["hookSpecificOutput"]["additionalContext"].startswith("PAY-4: news\n\nSeamTrail: nothing was saved in your last turn.") and "(the project “Pay”)" in d["hookSpecificOutput"]["additionalContext"]'
after_tool mcp_seamtrail_remember '{"content":"We picked Stripe","kind":"decision"}' "$(wrap '{\"memoryId\":\"m2\"}')" | run saved.sh
out=$(after_agent 'Next question' 'Saved.' false | run stop.sh)
if [ -z "$out" ] && [ ! -f "$DATA/saved-$S" ] && [ ! -f "$DATA/remind-$S" ]; then ok "turn: saved → quiet, no reminder waits"; else bad "turn: $out"; fi
fresh; : > "$FAKE/body"
quiet "turn: after a save the next message brings no reminder" "$(before_agent 'One more' | SEAMTRAIL_TOKEN=tok-1 run message.sh)"

echo "· hooks.json as Gemini CLI runs it (\${extensionPath} filled in, bash -c, a folder with a space)"
EXT="$W/ext dir/seamtrail"; mkdir -p "$W/ext dir" && cp -R "$P" "$EXT"
python3 - "$EXT" "$P/hooks/hooks.json" > "$W/commands" <<'EOF'
import json, sys
ext, path = sys.argv[1:3]
for event, groups in json.load(open(path))["hooks"].items():
    for g in groups:
        for h in g["hooks"]:
            print(event + "\t" + h["command"].replace("${extensionPath}", ext))
EOF
rm -f "$DATA"/*; printf 'p\n\n' > "$DATA/project-$S"
while IFS="$(printf '\t')" read -r event command; do
  case "$event" in
    SessionStart) input=$(session_start startup) ;;
    PreCompress) input=$(pre_compress) ;;
    BeforeAgent) input=$(before_agent 'hi PAY-4') ;;
    BeforeTool) input=$(before_tool mcp_seamtrail_remember '{"content":"x"}' seamtrail) ;;
    AfterTool) input=$(after_tool mcp_seamtrail_ask_seamtrail '{"question":"x"}' "$(wrap '{\"did\":[{\"done\":true}]}')") ;;
    AfterAgent) input=$(after_agent 'hi' 'PAY-4 done' false) ;;
  esac
  if printf '%s' "$input" | bash -c "$command" > "$W/out" 2> "$W/err" && [ ! -s "$W/err" ]; then
    case "$command" in
      *guard.sh*) grep -q '"chatId"' "$W/out" && ok "runs: $event guard" || bad "runs: $event guard printed nothing" ;;
      *) ok "runs: $event $(basename "$(printf '%s' "$command" | sed 's/.*\/scripts\///; s/"//g')")" ;;
    esac
  else bad "runs: $event $command → $(cat "$W/err")"; fi
done < "$W/commands"

[ $fail = 0 ] && echo "ALL PASSED" || echo "SOME FAILED"
[ $fail = 0 ]
