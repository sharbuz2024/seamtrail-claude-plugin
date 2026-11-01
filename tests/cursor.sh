#!/bin/sh
# SEAM-256 · the SeamTrail plugin for Cursor (plugins/seamtrail-cursor): every hook script fed sample inputs in Cursor's
# documented format (cursor.com/docs/hooks), under sh and dash, the guard and the ticket keeper with each JSON tool
# (jq, node, python3) and with none; and each
# command in hooks.json run as Cursor runs it, from the workspace folder. Nothing touches the home folder and nothing
# calls SeamTrail: notes go to a temporary folder, /hook/start to a stub on 127.0.0.1. Needs python3 (for checks).
#
#   sh tests/cursor.sh

here=$(CDPATH='' cd -- "$(dirname "$0")" && pwd)
REPO=$(CDPATH='' cd -- "$here/.." && pwd)
P="$REPO/plugins/seamtrail-cursor"
T=$(mktemp -d)
export HOME="$T/home" XDG_STATE_HOME="$T/state"
unset SEAMTRAIL_TOKEN SEAMTRAIL_URL CURSOR_PLUGIN_ROOT CURSOR_PROJECT_DIR CLAUDE_PROJECT_DIR CLAUDE_PLUGIN_DATA
mkdir -p "$HOME"
ST="$XDG_STATE_HOME/seamtrail/cursor"
C=0b1c2d3e-4f50-4a6b-8c7d-9e0f1a2b3c4d
PID=3f2a1b4c-5d6e-4f70-8a9b-0c1d2e3f4a5b
pass=0
fail=0
stub=""
cleanup() { [ -n "$stub" ] && kill "$stub" 2>/dev/null; rm -rf "$T"; }
trap cleanup EXIT INT TERM

ok() { echo "ok   $1"; pass=$((pass + 1)); }
bad() { echo "FAIL $1"; fail=$((fail + 1)); }
# check NAME PYTHON-EXPR DATA: the expression sees d (DATA as JSON; None when DATA is empty), raw (DATA itself) and
# want (env WANT).
check() {
  if printf '%s' "$3" | python3 -I -c '
import json, os, sys
raw = sys.stdin.read()
want = os.environ.get("WANT", "")
try:
    d = json.loads(raw) if raw.strip() else None
except Exception:
    d = "INVALID JSON"
sys.exit(0 if eval(sys.argv[1]) else 1)' "$2" 2>/dev/null; then ok "$1"; else bad "$1"; echo "       got: $3" | head -c 600; echo; fi
}
# A text as a JSON string literal.
sj() { python3 -I -c 'import json, sys; print(json.dumps(sys.argv[1]))' "$1"; }
# One JSON text, canonical (keys sorted), to compare answers.
canon() { python3 -I -c 'import json, sys; r = sys.stdin.read(); print(json.dumps(json.loads(r), sort_keys=True) if r.strip() else "")' 2>/dev/null; }

# The workspace: a git repository with a remote and a branch.
WS="$T/work space"
mkdir -p "$WS"
git init -q "$WS"
git -C "$WS" checkout -q -b seam-256-test
git -C "$WS" remote add origin git@github.com:acme/pay.git
git -C "$WS" -c user.name=Test -c user.email=test@example.com commit -q --allow-empty -m init

# Cursor's common input fields (cursor.com/docs/hooks · Common schema).
common() { # event, generation id
  printf '"conversation_id":"%s","generation_id":"%s","model":"claude-opus-4-7","hook_event_name":"%s","cursor_version":"3.1.0","workspace_roots":["%s"],"user_email":"dev@example.com","transcript_path":null' \
    "$C" "$2" "$1" "$WS"
}

# Bin folders with exactly the tools the scripts may use, plus one JSON tool (or none).
for tool in jq node python3 none; do
  mkdir -p "$T/bin-$tool"
  for u in awk cat curl dirname find git grep head mkdir mktemp mv rm sed tr uname xcode-select; do
    ln -s "$(command -v "$u")" "$T/bin-$tool/$u"
  done
  [ "$tool" = none ] || ln -s "$(command -v "$tool")" "$T/bin-$tool/$tool"
done

SHELLS=$(command -v sh)
command -v dash >/dev/null 2>&1 && SHELLS="$SHELLS $(command -v dash)"

# ---------------------------------------------------------------------------------------------------------------------
# The stub for /hook/start: answers from a control file, logs each request (path, query, Authorization).
cat > "$T/stub.py" <<'PY'
import http.server, json, sys, urllib.parse
ctl, log, portfile = sys.argv[1:4]
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        u = urllib.parse.urlsplit(self.path)
        with open(log, "a") as f:
            f.write(json.dumps({"path": u.path, "query": urllib.parse.parse_qs(u.query, keep_blank_values=True),
                                "auth": self.headers.get("Authorization")}) + "\n")
        with open(ctl) as f:
            c = json.load(f)
        body = c.get("body", "").encode("utf-8")
        self.send_response(c.get("status", 200))
        for k, v in c.get("headers", {}).items():
            self.send_header(k, v)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def log_message(self, *a):
        pass
s = http.server.HTTPServer(("127.0.0.1", 0), H)
with open(portfile, "w") as f:
    f.write(str(s.server_port))
s.serve_forever()
PY
BODY='## Project "Pay" — where it stands
Decisions: use \ backslashes, "quotes", tabs	and café ✓.'
# SeamTrail sends the name JSON-escaped and ASCII-only (hands jsonAscii): Pay \"Core\" caf\u00e9.
bs=$(printf '\134')
NAME="Pay $bs\"Core$bs\" caf${bs}u00e9"
python3 -I -c 'import json, sys; json.dump({"status": 200, "body": sys.argv[1], "headers": {"x-seamtrail-project": sys.argv[2], "x-seamtrail-project-name": sys.argv[3]}}, open(sys.argv[4], "w"))' \
  "$BODY" "$PID" "$NAME" "$T/stub.json"
python3 -I "$T/stub.py" "$T/stub.json" "$T/stub.log" "$T/stub.port" &
stub=$!
i=0
while [ ! -s "$T/stub.port" ] && [ "$i" -lt 100 ]; do sleep 0.1; i=$((i + 1)); done
URL="http://127.0.0.1:$(cat "$T/stub.port")/mcp"

for SH in $SHELLS; do
  echo "=== shell: $SH"
  rm -rf "$XDG_STATE_HOME" "$T/stub.log"

  # -------------------------------------------------------------------------------------------------------------------
  # start.sh (sessionStart)
  in=$(printf '{%s,"session_id":"%s","is_background_agent":false,"composer_mode":"agent"}' "$(common sessionStart g-0)" "$C")
  mkdir -p "$ST"
  out=$(cd "$P" && printf '%s' "$in" | SEAMTRAIL_TOKEN=tok-1 SEAMTRAIL_URL="$URL" CURSOR_PROJECT_DIR="$WS" CURSOR_PLUGIN_ROOT="$P" $SH "$P/scripts/start.sh")
  export WANT="$BODY"
  check "start: the server's text goes to the agent as additional_context, exactly" "d['additional_context'] == want" "$out"
  V=$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' "$P/.cursor-plugin/plugin.json")  # SEAM-273
  check "start: /hook/start got chat, folder, remote, branch, assistant=cursor, the plugin's version ($V) and the token" \
    "all(json.loads(l)['path'] == '/mcp/hook/start' for l in raw.splitlines()) and (lambda q, a: q['chat'] == ['$C'] and q['folder'] == ['$WS'] and q['remote'] == ['git@github.com:acme/pay.git'] and q['branch'] == ['seam-256-test'] and q['assistant'] == ['cursor'] and q['version'] == ['$V'] and a == 'Bearer tok-1')(json.loads(raw.splitlines()[-1])['query'], json.loads(raw.splitlines()[-1])['auth'])" \
    "$(cat "$T/stub.log")"

  : > "$T/stub.log"
  in2=$(printf '{%s,"session_id":"%s","is_background_agent":false}' "$(common sessionStart g-0)" "$C")
  out=$(cd "$WS" && printf '%s' "$in2" | SEAMTRAIL_TOKEN=tok-1 SEAMTRAIL_URL="$URL" $SH "$P/scripts/start.sh")
  check "start: without CURSOR_PROJECT_DIR the folder is the first workspace root" \
    "json.loads(raw.splitlines()[-1])['query']['folder'] == ['$WS']" "$(cat "$T/stub.log")"

  : > "$T/stub.log"
  out=$(printf '%s' "$in" | SEAMTRAIL_URL="$URL" CURSOR_PROJECT_DIR="$WS" $SH "$P/scripts/start.sh")
  check "start: no token → no call, nothing for the agent" "d == {}" "$out"
  if [ ! -s "$T/stub.log" ]; then ok "start: no token → nothing sent"; else bad "start: no token sent something"; fi

  python3 -I -c 'import json, sys; json.dump({"status": 500, "body": "boom"}, open(sys.argv[1], "w"))' "$T/stub.json"
  out=$(printf '%s' "$in" | SEAMTRAIL_TOKEN=tok-1 SEAMTRAIL_URL="$URL" CURSOR_PROJECT_DIR="$WS" $SH "$P/scripts/start.sh")
  check "start: the server fails → nothing for the agent, silently" "d == {}" "$out"
  python3 -I -c 'import json, sys; json.dump({"status": 200, "body": sys.argv[1], "headers": {"x-seamtrail-project": sys.argv[2], "x-seamtrail-project-name": sys.argv[3]}}, open(sys.argv[4], "w"))' \
    "$BODY" "$PID" "$NAME" "$T/stub.json"

  : > "$ST/old-note" && touch -t 202001010000 "$ST/old-note"
  printf '%s' "$in" | SEAMTRAIL_URL="$URL" $SH "$P/scripts/start.sh" > /dev/null
  [ -f "$ST/old-note" ] && bad "start: a note older than 60 days stayed" || ok "start: notes older than 60 days go"

  # -------------------------------------------------------------------------------------------------------------------
  # tickets.sh (beforeSubmitPrompt → person, afterAgentResponse → agent) with each JSON tool
  for tool in jq node python3; do
    rm -f "$ST/tickets-$C.jsonl"
    tk() { printf '%s' "$2" | PATH="$T/bin-$tool" $SH "$P/scripts/tickets.sh" "$1"; }
    tk person "$(printf '{%s,"prompt":"Fix PAY-4 and WEB-12 today, not pay-5","attachments":[]}' "$(common beforeSubmitPrompt g-1)")"
    tk agent "$(printf '{%s,"text":"Done with PAY-4.\\nShould I also do OPS-7?\\n"}' "$(common afterAgentResponse g-1)")"
    check "tickets ($tool): the numbers only, from both sides" \
      "[(x['r'], x['k']) for x in map(json.loads, raw.splitlines())] == [('person', ['PAY-4', 'WEB-12']), ('agent', ['OPS-7', 'PAY-4'])] and 'Fix' not in raw" \
      "$(cat "$ST/tickets-$C.jsonl" 2>/dev/null)"
    tk agent "$(printf '{%s,"text":"Which one, \\"A\\" or B? **Pick one?**\\n\\n"}' "$(common afterAgentResponse g-2)")"
    tk agent "$(printf '{%s,"text":"Is it done? Yes, it is done."}' "$(common afterAgentResponse g-3)")"
    for n in 1 2 3 4; do tk person "$(printf '{%s,"prompt":"About NEW-%s"}' "$(common beforeSubmitPrompt "g-p$n")" "$n")"; done
    check "tickets ($tool): only the newest 3 messages of each side" \
      "[x['k'] for x in map(json.loads, raw.splitlines()) if x['r'] == 'person'] == [['NEW-2'], ['NEW-3'], ['NEW-4']] and len([1 for l in raw.splitlines() if json.loads(l)['r'] == 'agent']) == 3" \
      "$(cat "$ST/tickets-$C.jsonl")"
  done

  # A long reply stays well inside the hook's 5 seconds.
  long=$(python3 -I -c 'import json, sys; b = chr(92); print(json.dumps({"conversation_id": sys.argv[1], "generation_id": "g-long", "text": ("A " + chr(34) + "quoted" + chr(34) + " line with " + b + b + " and PAY-4. ") * 3000 + "Shall I go on?"}))' "$C")
  t0=$(python3 -I -c 'import time; print(time.time())')
  printf '%s' "$long" | $SH "$P/scripts/tickets.sh" agent
  t1=$(python3 -I -c 'import time; print(time.time())')
  if python3 -I -c "import sys; sys.exit(0 if $t1 - $t0 < 4 else 1)"; then
    ok "tickets: a ${#long}-byte reply is read in time ($(python3 -I -c "print(round($t1 - $t0, 2))")s)"
  else bad "tickets: a long reply took $(python3 -I -c "print(round($t1 - $t0, 2))")s"; fi

  # -------------------------------------------------------------------------------------------------------------------
  # guard.sh (preToolUse): the same answer from jq, node and python3; nothing without a JSON tool
  rm -f "$ST/tickets-$C.jsonl"
  printf '%s\n%s\n' '{"r":"person","n":10,"k":["PAY-4","WEB-12"]}' '{"r":"agent","n":5,"k":["PAY-4"]}' > "$ST/tickets-$C.jsonl"
  pre() { printf '{%s,"tool_name":"%s","tool_input":%s,"tool_use_id":"tu-1","cwd":"%s"%s}' "$(common preToolUse g-5)" "$1" "$2" "$WS" "$3"; }
  guard_case() { # name, input, python expectation on d
    first=""
    same=yes
    for tool in jq node python3; do
      got=$(printf '%s' "$2" | PATH="$T/bin-$tool" $SH "$P/scripts/guard.sh")
      c=$(printf '%s' "$got" | canon)
      if [ "$tool" = jq ]; then first=$c; check "guard: $1" "$3" "$got"; elif [ "$c" != "$first" ]; then same=no; fi
    done
    [ "$same" = yes ] && ok "guard: $1 — jq, node and python3 agree" || bad "guard: $1 — the JSON tools disagree"
  }
  TAGS="'chatId': '$C', 'chatTickets': 'PAY-4,WEB-12'"
  guard_case "MCP:remember (no server named) gets the chat id and tickets" "$(pre MCP:remember '{"content":"Use Postgres","kind":"decision"}')" \
    "d == {'permission': 'allow', 'updated_input': {'content': 'Use Postgres', 'kind': 'decision', $TAGS}}"
  guard_case "MCP:set_chat_project gets them" "$(pre MCP:set_chat_project "{\"projectId\":\"$PID\"}")" \
    "d['updated_input'] == {'projectId': '$PID', $TAGS}"
  guard_case "MCP:search without SeamTrail's workingOn is left alone" "$(pre MCP:search '{"query":"x"}')" "d is None"
  guard_case "MCP:search with workingOn is SeamTrail's" "$(pre MCP:search '{"query":"x","workingOn":"Pay work"}')" \
    "d['updated_input'] == {'query': 'x', 'workingOn': 'Pay work', $TAGS}"
  guard_case "MCP:list_projects without workingOn is left alone" "$(pre MCP:list_projects '{}')" "d is None"
  guard_case "mcp__seamtrail__project_context is SeamTrail's" "$(pre mcp__seamtrail__project_context '{"projectId":"p"}')" \
    "d['updated_input'] == {'projectId': 'p', $TAGS}"
  guard_case "a server named, not SeamTrail → left alone" "$(pre MCP:remember '{"content":"x"}' ',"mcp_server_name":"memory"')" "d is None"
  guard_case "a server named SeamTrail → tagged" "$(pre MCP:remember '{"content":"x"}' ',"mcp_server_name":"plugin-seamtrail-cursor-seamtrail"')" \
    "d['updated_input'] == {'content': 'x', $TAGS}"
  guard_case "another server's tool → left alone" "$(pre MCP:web_search '{"q":"x"}')" "d is None"
  guard_case "mcp__linear__list_projects → left alone" "$(pre mcp__linear__list_projects '{"workingOn":"x"}')" "d is None"
  guard_case "a built-in tool → left alone" "$(pre Shell '{"command":"ls"}')" "d is None"
  guard_case "ListMcpResources on SeamTrail → left alone (not a tool call)" "$(pre ListMcpResources '{"server":"seamtrail"}')" "d is None"
  guard_case "a wrapped call {server, toolName, arguments} gets the id in its arguments" \
    "$(pre CallMcpTool '{"server":"plugin-seamtrail-cursor-seamtrail","toolName":"ask_seamtrail","arguments":{"question":"x"}}')" \
    "d['updated_input'] == {'server': 'plugin-seamtrail-cursor-seamtrail', 'toolName': 'ask_seamtrail', 'arguments': {'question': 'x', $TAGS}}"
  guard_case "a wrapped call with arguments as a JSON string keeps a JSON string" \
    "$(pre MCP '{"server":"seamtrail","toolName":"remember","arguments":"{\"content\":\"x\"}"}')" \
    "json.loads(d['updated_input']['arguments']) == {'content': 'x', $TAGS} and d['updated_input']['server'] == 'seamtrail'"
  guard_case "a wrapped call to another server → left alone" "$(pre CallMcpTool '{"server":"linear","toolName":"remember","arguments":{}}')" "d is None"
  guard_case "tool_input as a JSON string → read, answered as an object" "$(pre MCP:remember '"{\"content\":\"x\"}"')" \
    "d['updated_input'] == {'content': 'x', $TAGS}"
  guard_case "no conversation id → left alone" "$(printf '{"tool_name":"MCP:remember","tool_input":{"content":"x"}}')" "d is None"
  mv "$ST/tickets-$C.jsonl" "$T/tickets.keep"
  guard_case "no ticket numbers kept → chatId only" "$(pre MCP:remember '{"content":"x"}')" "d['updated_input'] == {'content': 'x', 'chatId': '$C'}"
  mv "$T/tickets.keep" "$ST/tickets-$C.jsonl"
  got=$(printf '%s' "$(pre MCP:remember '{"content":"x"}')" | PATH="$T/bin-none" $SH "$P/scripts/guard.sh"; echo "exit=$?")
  [ "$got" = "exit=0" ] && ok "guard: no JSON tool → no answer, exit 0 (the call goes on as it is)" || bad "guard without JSON tools: $got"

done

# -----------------------------------------------------------------------------------------------------------------------
# The manifests, and each hooks.json command run as Cursor runs it (a shell)
for f in "$P/.cursor-plugin/plugin.json" "$P/hooks/hooks.json" "$P/mcp.json" "$REPO/.cursor-plugin/marketplace.json"; do
  python3 -I -m json.tool "$f" > /dev/null 2>&1 && ok "valid JSON: ${f#"$REPO"/}" || bad "invalid JSON: $f"
done
check "plugin.json: a valid Cursor plugin name (lowercase, kebab-case)" \
  "d['name'] == 'seamtrail-cursor' and __import__('re').fullmatch(r'[a-z0-9]([a-z0-9.-]*[a-z0-9])?', d['name'])" \
  "$(cat "$P/.cursor-plugin/plugin.json")"
check "marketplace.json: lists this plugin by name, from this folder" \
  "[(p['name'], p['source']) for p in d['plugins']] == [('seamtrail-cursor', './plugins/seamtrail-cursor')] and d['owner']['name']" \
  "$(cat "$REPO/.cursor-plugin/marketplace.json")"
[ -f "$REPO/plugins/seamtrail-cursor/.cursor-plugin/plugin.json" ] && ok "marketplace.json: the source folder holds .cursor-plugin/plugin.json" || bad "marketplace source"
check "mcp.json: SeamTrail's server, signed in by Cursor (no token in the file)" \
  "d == {'mcpServers': {'seamtrail': {'url': 'https://mcp.seamtrail.com/mcp'}}}" "$(cat "$P/mcp.json")"
check "hooks.json: version 1, only Cursor's events, every command through sh with the plugin's root, never a relative path" \
  "d['version'] == 1 and set(d['hooks']) <= {'sessionStart','sessionEnd','preToolUse','postToolUse','postToolUseFailure','subagentStart','subagentStop','beforeShellExecution','afterShellExecution','beforeMCPExecution','afterMCPExecution','beforeReadFile','afterFileEdit','beforeSubmitPrompt','preCompact','stop','afterAgentResponse','afterAgentThought'} and all(h['command'].startswith('sh \"\${CURSOR_PLUGIN_ROOT') for hs in d['hooks'].values() for h in hs)" \
  "$(cat "$P/hooks/hooks.json")"
for s in "$P"/scripts/*.sh; do
  sh -n "$s" && { ! command -v dash >/dev/null 2>&1 || dash -n "$s"; } && ok "syntax: ${s#"$P"/}" || bad "syntax: $s"
done

# The plugin as Cursor may install it: a folder with spaces, scripts not executable.
I="$T/Cursor plugins/seamtrail cursor"
mkdir -p "$I" && cp -R "$P/." "$I/" && chmod a-x "$I"/scripts/*.sh
cmd() { python3 -I -c 'import json, sys; print(json.load(open(sys.argv[1]))["hooks"][sys.argv[2]][int(sys.argv[3])]["command"])' "$I/hooks/hooks.json" "$1" "${2:-0}"; }
rm -rf "$XDG_STATE_HOME"
in=$(printf '{%s,"session_id":"%s","is_background_agent":false}' "$(common sessionStart g-30)" "$C")
out=$(cd "$I" && printf '%s' "$in" | CURSOR_PLUGIN_ROOT="$I" SEAMTRAIL_TOKEN=tok-1 SEAMTRAIL_URL="$URL" CURSOR_PROJECT_DIR="$WS" sh -c "$(cmd sessionStart)")
check "hooks.json sessionStart command: runs from the plugin folder, hands over the context" \
  "'Pay' in d['additional_context'] and 'env' not in d" "$out"
printf '%s\n' '{"r":"person","n":3,"k":["PAY-4"]}' > "$ST/tickets-$C.jsonl"
out=$(cd "$I" && pre MCP:remember '{"content":"x"}' | CURSOR_PLUGIN_ROOT="$I" sh -c "$(cmd preToolUse)")
check "hooks.json preToolUse command: the guard answers" "d['updated_input']['chatId'] == '$C'" "$out"
(cd "$I" && printf '{%s,"prompt":"Look at OPS-9"}' "$(common beforeSubmitPrompt g-32)" | CURSOR_PLUGIN_ROOT="$I" sh -c "$(cmd beforeSubmitPrompt)")
grep -q OPS-9 "$ST/tickets-$C.jsonl" && ok "hooks.json beforeSubmitPrompt command: the ticket numbers are kept" || bad "hooks.json beforeSubmitPrompt"
(cd "$I" && printf '{%s,"text":"Done with OPS-10"}' "$(common afterAgentResponse g-33)" | CURSOR_PLUGIN_ROOT="$I" sh -c "$(cmd afterAgentResponse)")
grep -q OPS-10 "$ST/tickets-$C.jsonl" && ok "hooks.json afterAgentResponse command: the reply's ticket numbers are kept" || bad "hooks.json afterAgentResponse"
check "hooks.json: no turn-end hook and nothing after a tool: the plugin can never send a message in the person's name" \
  "not ({'stop', 'postToolUse', 'afterMCPExecution'} & set(d['hooks']))" "$(cat "$P/hooks/hooks.json")"
if grep -q followup_message "$P"/scripts/*.sh; then bad "a script still answers with a followup_message"; else ok "no script answers with a followup_message"; fi

echo
echo "$pass passed, $fail failed"
[ "$fail" = 0 ] && echo "ALL PASSED" || echo "SOME FAILED"
[ "$fail" = 0 ]
