#!/bin/sh
# SEAM-255 · tests for the VS Code plugin (plugins/seamtrail-vscode): its hook scripts fed sample hook inputs in the
# formats VS Code sends — the Copilot harness's camelCase JSON (the default for new chats since VS Code 1.143) and the
# snake_case JSON of the older Local harness and of Claude-style event names — and checked like test-215.sh.
# SeamTrail is a stub on 127.0.0.1 (never SeamTrail's real servers); every file goes to a temporary folder.
#   sh tests/vscode.sh                    TEST_SH=/bin/dash sh tests/vscode.sh   (the scripts run by dash)

ROOT=$(cd "$(dirname "$0")/.." && pwd)
P="$ROOT/plugins/seamtrail-vscode"
S="$P/com.github.copilot/scripts"
TPL="$ROOT/plugins/seamtrail/scripts"
SH="${TEST_SH:-/bin/sh}"
T=$(mktemp -d)
export T
fail=0
command -v python3 >/dev/null 2>&1 || { echo "FAIL python3 is needed to check the answers"; exit 1; }

ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }
# is NAME EXPR — the text on stdin makes the Python expression EXPR true. raw: the text; d: its JSON, else the text;
# body: the stub's chat-start text; env: the environment.
is() {
  _in=$(cat)
  if printf '%s' "$_in" | python3 -I -c '
import json, os, sys
raw = sys.stdin.read()
try:
    d = json.loads(raw)
except Exception:
    d = raw
body = open(os.path.join(os.environ["T"], "body.txt"), encoding="utf-8").read()
env = os.environ
sys.exit(0 if eval(sys.argv[1]) else 1)' "$2" 2>/dev/null; then
    ok "$1"
  else
    bad "$1"
    printf '     got: %.600s\n' "$_in"
  fi
}
empty() { if [ -z "$2" ]; then ok "$1"; else bad "$1"; printf '     got: %.600s\n' "$2"; fi; }
yes_() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }

unset CLAUDE_PLUGIN_DATA PLUGIN_DATA CLAUDE_PLUGIN_OPTION_SEAMTRAIL_TOKEN CLAUDE_PLUGIN_OPTION_SEAMTRAIL_URL XDG_STATE_HOME
export COPILOT_PLUGIN_DATA="$T/data"
export SEAMTRAIL_TOKEN=test-token
D="$COPILOT_PLUGIN_DATA"
PID=11111111-2222-3333-4444-555555555555

# ---------- a stub SeamTrail on 127.0.0.1: logs each request, answers like /hook/start ----------
cat > "$T/stub.py" <<'PY'
import http.server, json, os, sys, urllib.parse
T = sys.argv[1]
# The project's name as SeamTrail sends it: JSON-string content in ASCII (quotes and non-ASCII escaped).
NAME = 'Pay \\"v2\\" caf\\u00e9'
open(os.path.join(T, "name.txt"), "w").write(NAME)
BODY ='SeamTrail is your team\'s shared memory.\nProject "Pay" — a \\ backslash,\ta tab, “curly” quotes, café \U0001F680\r\n\nLast line'
open(os.path.join(T, "body.txt"), "w", encoding="utf-8", newline="").write(BODY.replace("\r", ""))
class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass
    def do_GET(self):
        u = urllib.parse.urlsplit(self.path)
        q = {k: v[0] for k, v in urllib.parse.parse_qs(u.query, keep_blank_values=True).items()}
        with open(os.path.join(T, "requests.log"), "a") as f:
            f.write(json.dumps({"path": u.path, "query": q, "auth": self.headers.get("Authorization")}) + "\n")
        chat = q.get("chat", "")
        if chat.startswith("err"):
            self.send_response(500); self.end_headers(); self.wfile.write(b"boom"); return
        body = b"" if chat.startswith("empty") else BODY.encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        if chat.startswith("ask"):
            self.send_header("x-seamtrail-project", "ask")
        elif not chat.startswith("none"):
            self.send_header("x-seamtrail-project", "11111111-2222-3333-4444-555555555555")
            self.send_header("x-seamtrail-project-name", NAME)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
s = http.server.HTTPServer(("127.0.0.1", 0), H)
open(os.path.join(T, "port.tmp"), "w").write(str(s.server_address[1]))
os.rename(os.path.join(T, "port.tmp"), os.path.join(T, "port"))
s.serve_forever()
PY
python3 -I "$T/stub.py" "$T" &
stub=$!
trap 'kill "$stub" 2>/dev/null; rm -rf "$T"' EXIT
trap 'exit 1' INT TERM
i=0
while [ ! -s "$T/port" ] && [ "$i" -lt 100 ]; do sleep 0.1; i=$((i + 1)); done
[ -s "$T/port" ] || { echo "FAIL the stub SeamTrail did not start"; exit 1; }
export SEAMTRAIL_URL="http://127.0.0.1:$(cat "$T/port")/mcp"
: > "$T/requests.log"
PNAME=$(cat "$T/name.txt")

# ---------- a git folder like a workspace, and PATHs with one JSON tool each (or none) ----------
R="$T/repo"
git init -q "$R" 2>/dev/null
git -C "$R" symbolic-ref HEAD refs/heads/PAY-4-checkout
git -C "$R" remote add origin git@github.com:acme/pay.git
git -C "$R" -c user.name=t -c user.email=t@example.com -c commit.gpgsign=false commit -q --allow-empty --no-verify -m init
mkbin() {
  _b="$T/bin-$1"; shift; mkdir -p "$_b"
  for _c in cat grep head sed tr rm mkdir mv find git curl mktemp dirname sort paste awk uname xcode-select xcrun wc env "$@"; do
    _p=$(command -v "$_c" 2>/dev/null) && ln -s "$_p" "$_b/$_c"
  done
  ln -s "$SH" "$_b/sh"
}
mkbin none; mkbin jq jq; mkbin node node; mkbin python3 python3
# Each JSON tool that is on this computer gets its run; the others are said and skipped.
tools=""
for b in jq node python3; do
  if command -v "$b" >/dev/null 2>&1; then tools="$tools $b"; else echo "note no $b on this computer: its run is skipped"; fi
done

# ---------- hook inputs as VS Code sends them ----------
c_start() { printf '{"sessionId":"%s","timestamp":1792700000000,"cwd":"%s","source":"new"}' "$1" "$R"; }
s_start() { printf '{"timestamp":"2026-10-22T10:00:00.000Z","cwd":"%s","session_id":"%s","hook_event_name":"SessionStart","transcript_path":"/tmp/t.json","source":"new"}' "$R" "$1"; }
c_prompt() { printf '{"sessionId":"%s","timestamp":1792700000000,"cwd":"%s","prompt":"%s"}' "$1" "$R" "$2"; }
s_prompt() { printf '{"timestamp":"2026-10-22T10:00:00.000Z","cwd":"%s","session_id":"%s","hook_event_name":"UserPromptSubmit","prompt":"%s"}' "$R" "$1" "$2"; }
c_pre() { printf '{"sessionId":"%s","timestamp":1792700000000,"cwd":"%s","toolName":"%s","toolArgs":%s}' "$1" "$R" "$2" "$3"; }
s_pre() { printf '{"timestamp":"2026-10-22T10:00:00.000Z","cwd":"%s","session_id":"%s","hook_event_name":"PreToolUse","tool_name":"%s","tool_input":%s,"tool_use_id":"tu-1"}' "$R" "$1" "$2" "$3"; }
c_post() { printf '{"sessionId":"%s","timestamp":1792700000000,"cwd":"%s","toolName":"%s","toolArgs":%s,"toolResult":%s}' "$1" "$R" "$2" "$3" "$4"; }
s_post() { printf '{"timestamp":"2026-10-22T10:00:00.000Z","cwd":"%s","session_id":"%s","hook_event_name":"PostToolUse","tool_name":"%s","tool_input":%s,"tool_use_id":"tu-1","tool_response":%s}' "$R" "$1" "$2" "$3" "$4"; }
c_stop() { printf '{"sessionId":"%s","timestamp":1792700000000,"cwd":"%s","transcriptPath":"/tmp/t.jsonl","stopReason":"end_turn","stop_hook_active":%s}' "$1" "$R" "$2"; }
s_stop() { printf '{"timestamp":"2026-10-22T10:00:00.000Z","cwd":"%s","session_id":"%s","hook_event_name":"Stop","transcript_path":"/tmp/t.json","stop_hook_active":%s}' "$R" "$1" "$2"; }
ok_text() { printf '{"resultType":"success","textResultForLlm":%s}' "$1"; }
last() { tail -1 "$T/requests.log"; }
count() { wc -l < "$T/requests.log" | tr -d ' '; }

echo "— the plugin's files (Agent Plugins 1.0, as VS Code reads them)"
python3 -I - "$P" "$ROOT" <<'PY' && ok "plugin.json, mcp.json, hooks.json and .github/plugin/marketplace.json are what VS Code expects" || { echo "FAIL the plugin's files"; exit 1; }
import json, os, re, sys
p, root = sys.argv[1:3]
m = json.load(open(os.path.join(p, "plugin.json")))
assert m["$schema"] == "https://agent-plugins.org/schemas/1.0.0/plugin.schema.json", m
assert set(m) <= {"$schema", "name", "version", "description", "author", "homepage", "repository", "license", "keywords", "extensions"}, m
assert re.fullmatch(r"(?!.*(?:--|\.\.))[a-z0-9](?:[a-z0-9.-]*[a-z0-9])?", m["name"]) and len(m["name"]) <= 64, m["name"]
assert set(m["author"]) <= {"name", "email", "url"}
mcp = json.load(open(os.path.join(p, "mcp.json")))
assert mcp["$schema"] == "https://agent-plugins.org/schemas/1.0.0/mcp.schema.json" and set(mcp) == {"$schema", "mcpServers"}
assert mcp["mcpServers"] == {"seamtrail": {"type": "streamable-http", "url": "https://mcp.seamtrail.com/mcp"}}, mcp
assert not os.path.exists(os.path.join(p, ".mcp.json")) and not os.path.exists(os.path.join(p, ".claude-plugin"))
h = json.load(open(os.path.join(p, "com.github.copilot", "hooks", "hooks.json")))
assert h["version"] == 1 and set(h) == {"version", "hooks"}
# The camelCase names VS Code's plugin parser and the Copilot harness both take.
assert set(h["hooks"]) == {"sessionStart", "userPromptSubmitted", "preToolUse", "postToolUse", "agentStop"}, set(h["hooks"])
want = {"sessionStart": ["start.sh"], "userPromptSubmitted": ["tickets.sh person"], "preToolUse": ["guard.sh"],
        "postToolUse": ["saved.sh", "saved.sh change", "picked.sh"], "agentStop": ["stop.sh"]}
for event, entries in h["hooks"].items():
    got = []
    for e in entries:
        assert set(e) == {"type", "bash", "powershell", "timeoutSec"}, e  # no matcher: VS Code drops it
        assert e["type"] == "command" and e["powershell"] == "exit 0" and isinstance(e["timeoutSec"], int) and e["timeoutSec"] <= 15, e
        b = e["bash"]
        assert b.startswith('sh "${PLUGIN_ROOT}"/com.github.copilot/scripts/') and b.endswith(" || true"), b
        script = b[len('sh "${PLUGIN_ROOT}"/com.github.copilot/scripts/'):-len(" || true")]
        assert os.path.isfile(os.path.join(p, "com.github.copilot", "scripts", script.split()[0])), script
        got.append(script)
    assert got == want[event], (event, got)
mk = json.load(open(os.path.join(root, ".github", "plugin", "marketplace.json")))
assert mk["name"] and mk["owner"]["name"] and len(mk["plugins"]) == 1
e = mk["plugins"][0]
assert e["name"] == m["name"] and e["version"] == m["version"], e
assert os.path.realpath(os.path.join(root, e["source"])) == os.path.realpath(p), e["source"]
PY

echo "— chat start (start.sh)"
out=$(c_start chat-1 | "$SH" "$S/start.sh")
printf '%s' "$out" | is "Copilot harness: SeamTrail's text is the chat's context, as JSON additionalContext (quotes, \\, tab, UTF-8 kept; CR dropped)" \
  'list(d) == ["additionalContext"] and d["additionalContext"] == body'
VV=$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' "$P/plugin.json"); export VV  # SEAM-273
last | is "registers the chat as a VS Code chat: chat id, folder, git remote and branch, assistant=vscode, the plugin's version, the token" \
  'd["path"] == "/mcp/hook/start" and d["query"] == {"remote": "git@github.com:acme/pay.git", "branch": "PAY-4-checkout", "chat": "chat-1", "folder": env["T"] + "/repo", "assistant": "vscode", "version": env["VV"]} and d["auth"] == "Bearer test-token"'
printf '%s\n%s\n' "$PID" "$PNAME" > "$T/want"
yes_ "keeps the chat's project (id and name, as SeamTrail sent them) for the turn-end check" 'cmp -s "$T/want" "$D/project-chat-1"'
out=$(s_start chat-2 | "$SH" "$S/start.sh")
printf '%s' "$out" | is "Local harness (snake_case): the same context, also inside hookSpecificOutput" \
  'd == {"additionalContext": body, "hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": body}}'
: > "$D/saved-chat-3"; printf 'x\n\n' > "$D/project-chat-3"; n=$(count)
out=$(c_start chat-3 | SEAMTRAIL_TOKEN= "$SH" "$S/start.sh")
yes_ "without a token: says nothing, calls nothing, and the chat still starts clean" \
  '[ -z "$out" ] && [ "$(count)" = "$n" ] && [ ! -f "$D/saved-chat-3" ] && [ ! -f "$D/project-chat-3" ]'
out=$(c_start err-1 | "$SH" "$S/start.sh"); rc=$?
yes_ "SeamTrail fails: silent, exit 0, no project kept" '[ -z "$out" ] && [ "$rc" = 0 ] && [ ! -f "$D/project-err-1" ]'
out=$(c_start empty-1 | "$SH" "$S/start.sh")
empty "nothing to say: no context added" "$out"
c_start ask-1 | "$SH" "$S/start.sh" > /dev/null
yes_ "more than one project (an older SeamTrail): kept as \"ask\"" '[ "$(sed -n 1p "$D/project-ask-1")" = ask ]'
c_start none-1 | "$SH" "$S/start.sh" > /dev/null
yes_ "no project: nothing kept, so the turn end never asks" '[ ! -f "$D/project-none-1" ]'
(cd "$R" && printf '{"sessionId":"chat-pwd"}' | "$SH" "$S/start.sh" > /dev/null)
last | is "no cwd in the input: the hook's own folder (VS Code runs hooks in the workspace)" \
  'd["query"]["folder"] == env["T"] + "/repo" and d["query"]["remote"] == "git@github.com:acme/pay.git"'
c_start chat-p | env -u COPILOT_PLUGIN_DATA PLUGIN_DATA="$T/pdata" "$SH" "$S/start.sh" > /dev/null
yes_ "data folder: PLUGIN_DATA when COPILOT_PLUGIN_DATA is not set" '[ -f "$T/pdata/project-chat-p" ]'
c_start chat-x | env -u COPILOT_PLUGIN_DATA -u PLUGIN_DATA XDG_STATE_HOME="$T/xdg" "$SH" "$S/start.sh" > /dev/null
yes_ "data folder: \$XDG_STATE_HOME/seamtrail/vscode when VS Code gives none" '[ -f "$T/xdg/seamtrail/vscode/project-chat-x" ]'
c_start chat-h | env -u COPILOT_PLUGIN_DATA -u PLUGIN_DATA -u XDG_STATE_HOME HOME="$T/home" "$SH" "$S/start.sh" > /dev/null
yes_ "data folder: ~/.local/state/seamtrail/vscode by default" '[ -f "$T/home/.local/state/seamtrail/vscode/project-chat-h" ]'

echo "— the tickets the person names (tickets.sh person)"
for b in $tools; do
  f="$D/tickets-tk-$b.jsonl"
  c_prompt "tk-$b" "Fix PAY-4 and ABC-12, not pay-5" | PATH="$T/bin-$b" "$SH" "$S/tickets.sh" person
  c_prompt "tk-$b" "Fix PAY-4 and ABC-12, not pay-5" | PATH="$T/bin-$b" "$SH" "$S/tickets.sh" person
  cat "$f" | is "$b: keeps the ticket numbers only, once for the same message" \
    '[json.loads(l) for l in raw.splitlines()] == [{"r": "person", "n": 31, "k": ["ABC-12", "PAY-4"]}]'
  for k in DEV-1 DEV-2 DEV-3; do c_prompt "tk-$b" "and $k" | PATH="$T/bin-$b" "$SH" "$S/tickets.sh" person; done
  cat "$f" | is "$b: only the person's last 3 messages" '[json.loads(l)["k"] for l in raw.splitlines()] == [["DEV-1"], ["DEV-2"], ["DEV-3"]]'
done
s_prompt tk-s "Look at OPS-7" | "$SH" "$S/tickets.sh" person
cat "$D/tickets-tk-s.jsonl" | is "Local harness input (session_id) works the same" 'json.loads(raw)["k"] == ["OPS-7"]'
c_prompt tk-n "Fix PAY-4" | PATH="$T/bin-none" "$SH" "$S/tickets.sh" person
yes_ "no JSON tool: keeps nothing, says nothing" '[ ! -f "$D/tickets-tk-n.jsonl" ]'
c_prompt tk-x "Fix PAY-4" | "$SH" "$S/tickets.sh" other
yes_ "an unknown role does nothing" '[ ! -f "$D/tickets-tk-x.jsonl" ]'

echo "— before each SeamTrail tool call (guard.sh)"
printf '%s\n%s\n' '{"r":"person","n":9,"k":["PAY-4"]}' '{"r":"person","n":20,"k":["ABC-12","PAY-4"]}' > "$D/tickets-g1.jsonl"
for b in $tools; do
  out=$(c_pre g1 seamtrail-remember '{"note":"x","projectId":"p"}' | PATH="$T/bin-$b" "$SH" "$S/guard.sh")
  printf '%s' "$out" | is "$b, Copilot harness: modifiedArgs = the call's arguments + chatId + chatTickets, nothing else" \
    'd == {"modifiedArgs": {"note": "x", "projectId": "p", "chatId": "g1", "chatTickets": "ABC-12,PAY-4"}}'
  out=$(c_pre g1 seamtrail-search_memory '"{\"query\":\"why \\\"v2\\\"\",\"workingOn\":\"w\"}"' | PATH="$T/bin-$b" "$SH" "$S/guard.sh")
  printf '%s' "$out" | is "$b: arguments handed over as a JSON string come back as an object" \
    'd == {"modifiedArgs": {"query": "why \"v2\"", "workingOn": "w", "chatId": "g1", "chatTickets": "ABC-12,PAY-4"}}'
  out=$(s_pre g1 mcp_seamtrail_remember '{"note":"x"}' | PATH="$T/bin-$b" "$SH" "$S/guard.sh")
  printf '%s' "$out" | is "$b, Local harness: the same arguments also as hookSpecificOutput.updatedInput" \
    'd == {"modifiedArgs": {"note": "x", "chatId": "g1", "chatTickets": "ABC-12,PAY-4"}, "hookSpecificOutput": {"hookEventName": "PreToolUse", "updatedInput": {"note": "x", "chatId": "g1", "chatTickets": "ABC-12,PAY-4"}}}'
  out=$(printf '{"sessionId":"g2","toolName":"seamtrail-list_projects"}' | PATH="$T/bin-$b" "$SH" "$S/guard.sh")
  printf '%s' "$out" | is "$b: a call without arguments, a chat without tickets: chatId only" 'd == {"modifiedArgs": {"chatId": "g2"}}'
  out=$(c_pre g1 seamtrail-remember '"not json"' | PATH="$T/bin-$b" "$SH" "$S/guard.sh")
  empty "$b: arguments it cannot read: the call goes on as it is" "$out"
  out=$(c_pre g1 seamtrail-remember '["a"]' | PATH="$T/bin-$b" "$SH" "$S/guard.sh")
  empty "$b: arguments that are not an object: the call goes on as it is" "$out"
done
for name in mcp__seamtrail__ask_seamtrail mcp_seamtrail_project_context SeamTrail-Get_Chain seamtrail/fetch; do
  out=$(c_pre g2 "$name" '{}' | "$SH" "$S/guard.sh")
  printf '%s' "$out" | is "SeamTrail's tool named $name: tagged" 'd["modifiedArgs"]["chatId"] == "g2"'
done
for name in bash edit mcp_github_get_issue github-mcp-server-search_code memory-remember runInTerminal; do
  out=$(c_pre g2 "$name" '{"command":"ls"}' | "$SH" "$S/guard.sh")
  empty "another tool ($name): untouched (VS Code runs the guard before every tool)" "$out"
done
out=$(c_pre g2 editFiles '{"path":"seamtrail-hands/src/SeamTrail.ts"}' | "$SH" "$S/guard.sh")
empty "another tool whose input mentions seamtrail (a path): untouched" "$out"
out=$(printf '{"toolName":"seamtrail-remember","toolArgs":{}}' | "$SH" "$S/guard.sh")
empty "no chat id: untouched" "$out"
out=$(c_pre g1 seamtrail-remember '{"note":"x"}' | PATH="$T/bin-none" "$SH" "$S/guard.sh"); rc=$?
yes_ "no JSON tool: untouched, exit 0 (a failing guard would deny the call)" '[ -z "$out" ] && [ "$rc" = 0 ]'

echo "— after SeamTrail tools: saved this turn (saved.sh, saved.sh change)"
sv() { if [ -f "$D/saved-sv" ]; then got=saved; else got=not; fi; if [ "$got" = "$2" ]; then ok "$1 → $got"; else bad "$1 → $got (wanted $2)"; fi; rm -f "$D/saved-sv"; }
note_text='"{\"memoryId\":\"m1\",\"kind\":\"fact\"}"'
for t in seamtrail-remember seamtrail-resolve mcp_seamtrail_settle_question mcp__seamtrail__widen_memory; do
  c_post sv "$t" '{"note":"x"}' "$(ok_text "$note_text")" | "$SH" "$S/saved.sh"; sv "$t" saved
done
c_post sv memory-remember '{"note":"x"}' "$(ok_text "$note_text")" | "$SH" "$S/saved.sh"; sv "another server's remember" not
c_post sv editFiles '{"path":"seamtrail/remember"}' "$(ok_text '"ok"')" | "$SH" "$S/saved.sh"; sv "another tool whose input mentions seamtrail/remember" not
c_post sv seamtrail-remember '{"note":"x"}' '{"resultType":"failure","textResultForLlm":"refused"}' | "$SH" "$S/saved.sh"; sv "remember that failed" not
change='"{\"answer\":\"Done: moved\",\"did\":[{\"what\":\"move ticket\",\"done\":true,\"verified\":true}]}"'
c_post sv seamtrail-ask_seamtrail '{"question":"x"}' "$(ok_text "$change")" | "$SH" "$S/saved.sh"; sv "saved.sh (notes) after ask_seamtrail — VS Code runs every after-tool hook" not
c_post sv seamtrail-set_chat_project "{\"projectId\":\"$PID\"}" "$(ok_text '"ok"')" | "$SH" "$S/saved.sh"; sv "saved.sh (notes) after set_chat_project" not
c_post sv seamtrail-remember '{"note":"x"}' "$(ok_text "$note_text")" | "$SH" "$S/saved.sh" change; sv "saved.sh change after remember" not
c_post sv seamtrail-ask_seamtrail '{"question":"x"}' "$(ok_text '"{\"answer\":\"No ticket found\",\"checked\":[\"search_jira\"]}"')" | "$SH" "$S/saved.sh" change; sv "ask_seamtrail, a question only" not
c_post sv seamtrail-ask_seamtrail '{"question":"x"}' "$(ok_text "$change")" | "$SH" "$S/saved.sh" change; sv "ask_seamtrail, a real change (Copilot textResultForLlm)" saved
s_post sv mcp_seamtrail_ask_seamtrail '{"question":"x"}' '[{"type":"text","text":"{\"did\":[{\"what\":\"move\",\"done\":true}]}"}]' | "$SH" "$S/saved.sh" change; sv "ask_seamtrail, a real change (Local, content blocks)" saved
s_post sv mcp_seamtrail_ask_seamtrail '{"question":"x"}' '{"structuredContent":{"did":[{"what":"move","done":true}]}}' | "$SH" "$S/saved.sh" change; sv "ask_seamtrail, a real change (Local, structured)" saved
c_post sv seamtrail-ask_seamtrail '{"question":"x"}' "$(ok_text '"{\"answer\":\"Not done\",\"did\":[{\"what\":\"move\",\"done\":false,\"error\":\"Jira refused\"}]}"')" | "$SH" "$S/saved.sh" change; sv "ask_seamtrail, a change that failed" not
c_post sv seamtrail-ask_seamtrail '{"question":"x"}' "$(ok_text '"{\"tool\":\"promotion_rules\",\"result\":{\"checklist\":[{\"label\":\"flag\",\"done\":true}]}}"')" | "$SH" "$S/saved.sh" change; sv "ask_seamtrail, a read that happens to hold done:true" not
c_post sv seamtrail-undo_change '{"handle":"h"}' "$(ok_text '"Undone — reading it back confirms it."')" | "$SH" "$S/saved.sh" change; sv "undo_change" saved
s_post sv mcp_seamtrail_undo_change '{"handle":"h"}' '{"isError":true,"content":[{"type":"text","text":"That is not an undo handle"}]}' | "$SH" "$S/saved.sh" change; sv "undo_change that failed (Local isError)" not
c_post sv seamtrail-undo_change '{"handle":"h"}' '{"resultType":"failure","textResultForLlm":"That is not an undo handle"}' | "$SH" "$S/saved.sh" change; sv "undo_change that failed (Copilot resultType)" not
printf '{"timestamp":"2026-10-22T10:00:00.000Z","cwd":"/w","session_id":"sv","hook_event_name":"PostToolUse","tool_name":"seamtrail-remember","tool_input":{"note":"x"},"tool_result":{"result_type":"success","text_result_for_llm":"{\\"memoryId\\":\\"m1\\"}"}}' | "$SH" "$S/saved.sh"
sv "remember (Copilot harness, Claude-style names: tool_result)" saved

echo "— after set_chat_project: the chat's project (picked.sh)"
P2=22222222-3333-4444-5555-666666666666
P3=33333333-4444-5555-6666-777777777777
pk() { if [ -f "$D/project-pk" ]; then sed -n 1p "$D/project-pk"; else echo none; fi; }
c_post pk seamtrail-set_chat_project "\"{\\\"projectId\\\":\\\"$P2\\\"}\"" "$(ok_text '"Set."')" | "$SH" "$S/picked.sh"
yes_ "Copilot harness, arguments as a JSON string: the picked project is kept (id, empty name)" '[ "$(cat "$D/project-pk")" = "$P2" ] && [ "$(wc -l < "$D/project-pk" | tr -d " ")" = 2 ]'
c_post pk seamtrail-set_chat_project "{\"projectId\":\"$P3\"}" "$(ok_text '"Set."')" | "$SH" "$S/picked.sh"
yes_ "Copilot harness, arguments as an object" '[ "$(pk)" = "$P3" ]'
s_post pk mcp_seamtrail_set_chat_project "{\"projectId\":\"$P2\"}" '"Set."' | "$SH" "$S/picked.sh"
yes_ "Local harness" '[ "$(pk)" = "$P2" ]'
c_post pk seamtrail-remember "{\"note\":\"x\",\"projectId\":\"$P3\"}" "$(ok_text "$note_text")" | "$SH" "$S/picked.sh"
yes_ "another SeamTrail tool with a projectId: the chat's project is untouched" '[ "$(pk)" = "$P2" ]'
c_post pk other-set_chat_project "{\"projectId\":\"$P3\"}" "$(ok_text '"Set."')" | "$SH" "$S/picked.sh"
yes_ "another server's set_chat_project: untouched" '[ "$(pk)" = "$P2" ]'
c_post pk editFiles "{\"path\":\"seamtrail/set_chat_project\",\"projectId\":\"$P3\"}" "$(ok_text '"ok"')" | "$SH" "$S/picked.sh"
yes_ "another tool whose input mentions seamtrail and a projectId: untouched" '[ "$(pk)" = "$P2" ]'
c_post pk seamtrail-set_chat_project "{\"projectId\":\"$P3\"}" '{"resultType":"failure","textResultForLlm":"Not on that project"}' | "$SH" "$S/picked.sh"
yes_ "refused: untouched" '[ "$(pk)" = "$P2" ]'
c_post pk seamtrail-set_chat_project '{"none":true}' "$(ok_text "\"{\\\"projectId\\\":\\\"$P3\\\"}\"")" | "$SH" "$S/picked.sh"
yes_ "\"No project\": forgotten, even when the reply names a project" '[ "$(pk)" = none ]'
s_post pk mcp_seamtrail_set_chat_project '{"none":true}' "{\"projectId\":\"$P3\"}" | "$SH" "$S/picked.sh"
yes_ "\"No project\" (Local, a structured reply with a projectId): still none" '[ "$(pk)" = none ]'

echo "— turn end (stop.sh), the Claude Code plugin's words"
mkdir -p "$T/tpl"
same_as_template() { # name, vs-out — the template's stop.sh on the same project file must give the same reason
  cp "$D/project-st" "$T/tpl/project-st" 2>/dev/null
  tpl=$(printf '{"session_id":"st","stop_hook_active":false}' | CLAUDE_PLUGIN_DATA="$T/tpl" "$SH" "$TPL/stop.sh")
  printf '%s\n%s' "$2" "$tpl" | is "$1" 'json.loads(raw.split(chr(10))[0])["reason"] == json.loads(raw.split(chr(10))[1])["reason"]'
}
printf '%s\n%s\n' "$PID" "$PNAME" > "$D/project-st"
out=$(c_stop st false | "$SH" "$S/stop.sh")
printf '%s' "$out" | is "Copilot harness: asks once, top-level decision block, names the project (JSON-escaped name decoded)" \
  'list(d) == ["decision", "reason"] and d["decision"] == "block" and "with projectId 11111111-2222-3333-4444-555555555555 (the project “Pay \"v2\" café”)" in d["reason"] and "This chat saves only into that project: if something belongs to another project, tell your person instead" in d["reason"]'
same_as_template "Copilot harness: the reason is word for word the Claude Code plugin's" "$out"
out=$(s_stop st false | "$SH" "$S/stop.sh")
printf '%s' "$out" | is "Local harness: also inside hookSpecificOutput (Stop)" \
  'd["decision"] == "block" and d["hookSpecificOutput"] == {"hookEventName": "Stop", "decision": "block", "reason": d["reason"]}'
out=$(c_stop st true | "$SH" "$S/stop.sh")
empty "asked once already this turn (stop_hook_active): never twice" "$out"
: > "$D/saved-st"
out=$(c_stop st false | "$SH" "$S/stop.sh")
yes_ "saved this turn: quiet, and the next turn starts clean" '[ -z "$out" ] && [ ! -f "$D/saved-st" ]'
printf 'ask\n\n' > "$D/project-st"
out=$(c_stop st false | "$SH" "$S/stop.sh")
printf '%s' "$out" | is "two projects matched (an older SeamTrail): the same words as before" '"more than one SeamTrail project" in d["reason"]'
same_as_template "two projects matched: word for word the Claude Code plugin's" "$out"
printf '%s\n\n' "$P2" > "$D/project-st"
out=$(c_stop st false | "$SH" "$S/stop.sh")
same_as_template "a project picked in the chat (id only): word for word the Claude Code plugin's" "$out"
rm -f "$D/project-st"
out=$(c_stop st false | "$SH" "$S/stop.sh")
empty "no project: never asks" "$out"

echo "— one chat from start to end (Copilot harness)"
c_start flow | "$SH" "$S/start.sh" > /dev/null
c_prompt flow "Let us finish PAY-4" | "$SH" "$S/tickets.sh" person
out=$(c_pre flow seamtrail-remember '{"note":"PAY-4 ships Friday"}' | "$SH" "$S/guard.sh")
printf '%s' "$out" | is "the call carries the chat and its ticket" 'd["modifiedArgs"] == {"note": "PAY-4 ships Friday", "chatId": "flow", "chatTickets": "PAY-4"}'
c_post flow seamtrail-remember '{"note":"PAY-4 ships Friday"}' "$(ok_text "$note_text")" | "$SH" "$S/saved.sh"
out=$(c_stop flow false | "$SH" "$S/stop.sh")
empty "turn 1: a note was saved, so no reminder" "$out"
out=$(c_stop flow false | "$SH" "$S/stop.sh")
printf '%s' "$out" | is "turn 2: nothing saved, so one reminder naming the project" 'd["decision"] == "block" and "11111111-2222-3333-4444-555555555555" in d["reason"]'
out=$(c_stop flow true | "$SH" "$S/stop.sh")
empty "turn 2, after the reminder: never twice" "$out"
c_post flow seamtrail-set_chat_project "{\"projectId\":\"$P3\"}" "$(ok_text '"Set."')" | "$SH" "$S/picked.sh"
out=$(c_stop flow false | "$SH" "$S/stop.sh")
printf '%s' "$out" | is "turn 3: the person switched the chat's project: the reminder names the new one" '"with projectId 33333333-4444-5555-6666-777777777777:" in d["reason"]'
c_post flow seamtrail-set_chat_project '{"none":true}' "$(ok_text '"Set."')" | "$SH" "$S/picked.sh"
out=$(c_stop flow false | "$SH" "$S/stop.sh")
empty "turn 4: \"No project\": never asks" "$out"

echo "— the hook commands as VS Code runs them"
mkdir -p "$T/with space"; cp -R "$P" "$T/with space/seamtrail-vscode"
SP="$T/with space/seamtrail-vscode"
# cmd EVENT INDEX MODE: the hook's bash command, its ${PLUGIN_ROOT} replaced the way VS Code does (vscode: a path with a
# space goes in single quotes, the quotes around the token included), or left for the shell (shell).
cmd() {
  python3 -I - "$SP/com.github.copilot/hooks/hooks.json" "$1" "$2" "$3" "$SP" <<'PY'
import json, re, sys
path, event, index, mode, root = sys.argv[1:6]
c = json.load(open(path))["hooks"][event][int(index)]["bash"]
if mode == "vscode":
    if re.fullmatch(r"[a-zA-Z0-9_./:-]+", root):
        c = c.replace("${PLUGIN_ROOT}", root)
    else:
        q = "'" + root.replace("'", "'\\''") + "'"
        c = re.sub(r"([\"']?)\$\{PLUGIN_ROOT\}\1", lambda m: q, c)
print(c)
PY
}
for mode in vscode shell; do
  out=$(c_start cmd-$mode | PLUGIN_ROOT="$SP" PATH="$T/bin-jq" "$SH" -c "$(cmd sessionStart 0 $mode)")
  printf '%s' "$out" | is "$mode: sessionStart from a folder with a space gives the context" 'd["additionalContext"] == body'
  out=$(c_pre cmd-$mode seamtrail-remember '{"note":"x"}' | PLUGIN_ROOT="$SP" PATH="$T/bin-jq" "$SH" -c "$(cmd preToolUse 0 $mode)")
  printf '%s' "$out" | is "$mode: preToolUse tags SeamTrail's call" 'd == {"modifiedArgs": {"note": "x", "chatId": "cmd-'"$mode"'"}}'
  out=$(c_stop cmd-$mode false | PLUGIN_ROOT="$SP" PATH="$T/bin-jq" "$SH" -c "$(cmd agentStop 0 $mode)")
  printf '%s' "$out" | is "$mode: agentStop asks once" 'd["decision"] == "block"'
done
out=$(c_pre cmd-x seamtrail-remember '{"note":"x"}' | env -u PLUGIN_ROOT PATH="$T/bin-jq" "$SH" -c "$(cmd preToolUse 0 shell)" 2>/dev/null); rc=$?
yes_ "a plugin folder that cannot be found: preToolUse still exits 0 with nothing (the tool call is not denied)" '[ -z "$out" ] && [ "$rc" = 0 ]'
rc=0
for e in sessionStart:0 userPromptSubmitted:0 preToolUse:0 postToolUse:0 postToolUse:1 postToolUse:2 agentStop:0; do
  printf '{"sessionId":"cmd-all","toolName":"bash","toolArgs":{},"prompt":"hi"}' | PLUGIN_ROOT="$SP" PATH="$T/bin-jq" "$SH" -c "$(cmd "${e%:*}" "${e#*:}" vscode)" > /dev/null 2>&1 || rc=1
done
yes_ "every hook command exits 0" '[ "$rc" = 0 ]'

echo "— the Claude Code plugin as it is, on the same VS Code inputs (notes, not failures)"
o=$(c_start tpl-1 | env -u COPILOT_PLUGIN_DATA "$SH" "$TPL/start.sh")
if printf '%s' "$o" | python3 -I -c 'import json,sys; json.loads(sys.stdin.read())' 2>/dev/null; then echo "note start.sh: JSON"; else echo "note start.sh prints plain text: VS Code reads hook output as JSON, so the chat gets no context"; fi
last | python3 -I -c 'import json,sys; q=json.load(sys.stdin)["query"]; print("note start.sh sends no assistant: SeamTrail labels the chat Claude Code" if "assistant" not in q else "note start.sh sends assistant")'
o=$(c_pre tpl-1 seamtrail-remember '{"note":"x"}' | "$SH" "$TPL/guard.sh")
[ -z "$o" ] && echo "note guard.sh adds no chatId: VS Code's tool names and input fields are not Claude Code's"
o=$(c_stop tpl-1 false | env -u COPILOT_PLUGIN_DATA "$SH" "$TPL/stop.sh")
[ -z "$o" ] && echo "note stop.sh never asks: VS Code sets no CLAUDE_PLUGIN_DATA, so nothing is kept (no project, no saved mark)"

[ "$fail" = 0 ] && echo "ALL PASSED ($SH)" || echo "SOME FAILED ($SH)"
[ "$fail" = 0 ]
