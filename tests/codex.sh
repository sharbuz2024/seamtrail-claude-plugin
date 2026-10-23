#!/bin/sh
# SEAM-252 · The SeamTrail plugin for Codex (plugins/seamtrail-codex), tested without Codex and without SeamTrail. Its
# scripts are fed hook inputs in Codex's documented format (learn.chatgpt.com/docs/hooks; openai/codex codex-rs/hooks);
# a stand-in curl answers like SeamTrail's /hook/start and /hook/message and records what would be sent (nothing goes
# online); the turn-end words and the saved marker are compared with the Claude Code plugin's (plugins/seamtrail, the
# template); and every hook in hooks.json is run the way Codex runs it: ${PLUGIN_ROOT} replaced, the command line
# through the shell in the session's folder, the input JSON on stdin. Run: sh tests/codex.sh

here=$(cd "$(dirname "$0")/.." && pwd)
P="$here/plugins/seamtrail-codex"
T="$here/plugins/seamtrail"
PY=$(command -v python3) || { echo "SOME FAILED: python3 is needed to check the results"; exit 1; }
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT INT TERM
unset PLUGIN_DATA PLUGIN_ROOT CLAUDE_PLUGIN_DATA CLAUDE_PLUGIN_ROOT SEAMTRAIL_TOKEN SEAMTRAIL_URL XDG_STATE_HOME
fail=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }
check() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 — got [$2], wanted [$3]"; fi; }
# name, JSON text, python lines run with the parsed JSON as d (assert in them)
pyck() {
  if printf '%s' "$2" | "$PY" -c "import json, sys
d = json.loads(sys.stdin.read())
$3" 2>"$W/pyerr"; then ok "$1"; else bad "$1 — $(tail -1 "$W/pyerr") — output: [$2]"; fi
}
S=019a7c3e-5b1d-7f20-9e4a-2c8d1f6b0a31        # a Codex session (thread) id
PID=6f1c2a9e-3b4d-4e5f-8a7b-9c0d1e2f3a4b      # a SeamTrail project id
BS=$(printf '\134')   # a backslash: SeamTrail sends a project's name JSON-escaped (\u + 4 hex digits for non-ASCII)

# ── A stand-in curl: never goes online; records its arguments (one per line, then ----) and answers like SeamTrail.
mkdir -p "$W/fake"
cat > "$W/fake/curl" <<'EOF'
#!/bin/sh
for a in "$@"; do printf '%s\n' "$a"; done >> "${FAKE_LOG:?}"
echo ---- >> "$FAKE_LOG"
[ "${FAKE_FAIL:-0}" = 1 ] && exit 22
headers=""; body=""
while [ $# -gt 0 ]; do
  case "$1" in
    -D) headers="$2"; shift 2 ;;
    -o) body="$2"; shift 2 ;;
    -H|--data-urlencode|--max-time) shift 2 ;;
    *) shift ;;
  esac
done
if [ -n "$headers" ]; then
  { printf 'HTTP/2 200\r\ncontent-type: text/plain; charset=utf-8\r\n'
    [ -n "$FAKE_PROJECT" ] && printf 'x-seamtrail-project: %s\r\n' "$FAKE_PROJECT"
    [ -n "$FAKE_NAME" ] && printf 'X-SeamTrail-Project-Name: %s\r\n' "$FAKE_NAME"
    printf '\r\n'; } > "$headers"
fi
if [ -n "$body" ]; then printf '%s' "$FAKE_BODY" > "$body"; else printf '%s' "$FAKE_BODY"; fi
exit 0
EOF
chmod +x "$W/fake/curl"
FAKE_LOG="$W/curl.log"; export FAKE_LOG
PATH="$W/fake:$PATH"; export PATH
[ "$(command -v curl)" = "$W/fake/curl" ] || { echo "SOME FAILED: the stand-in curl is not first on PATH"; exit 1; }
sent() { grep -qxF -- "$1" "$FAKE_LOG"; }   # was this argument given to curl?

# ── Toolboxes: a PATH with the basic tools and only the JSON tool named (jq, node, python3, or none).
box() {
  b="$W/box-$1"; shift; mkdir -p "$b"
  for t in sh cat grep head sed rm mkdir find mv sort paste tr git mktemp uname xcode-select "$@"; do
    p=$(command -v "$t" 2>/dev/null) && ln -sf "$p" "$b/$t"
  done
  ln -sf "$W/fake/curl" "$b/curl"
}
box jq jq; box node node; box python3 python3; box none

# ── Codex's hook inputs (field names from codex-rs/hooks/src/events/*.rs).
start_in() { printf '{"session_id":"%s","transcript_path":null,"cwd":"%s","hook_event_name":"SessionStart","model":"gpt-5.5-codex","permission_mode":"default","source":"%s"}' "$S" "$1" "${2:-startup}"; }
prompt_in() { printf '{"session_id":"%s","turn_id":"t1","transcript_path":null,"cwd":"/w","hook_event_name":"UserPromptSubmit","model":"gpt-5.5-codex","permission_mode":"default","prompt":"%s"%s}' "$S" "$1" "${2:-}"; }
pre_in() { printf '{"session_id":"%s","turn_id":"t1","transcript_path":null,"cwd":"/w","hook_event_name":"PreToolUse","model":"gpt-5.5-codex","permission_mode":"default","tool_name":"%s","tool_input":%s,"tool_use_id":"call_1"%s}' "$S" "$1" "$2" "${3:-}"; }
post_in() { printf '{"session_id":"%s","turn_id":"t1","transcript_path":null,"cwd":"/w","hook_event_name":"PostToolUse","model":"gpt-5.5-codex","permission_mode":"default","tool_name":"%s","tool_input":%s,"tool_use_id":"call_1","tool_response":%s}' "$S" "$1" "$2" "$3"; }
stop_in() { printf '{"session_id":"%s","turn_id":"t1","transcript_path":null,"cwd":"/w","hook_event_name":"Stop","model":"gpt-5.5-codex","permission_mode":"default","stop_hook_active":%s,"last_assistant_message":"%s"}' "$S" "$1" "${2:-Done.}"; }

# A git folder like a person's repository: an origin and a branch named after a ticket.
REPO="$W/repo"
git init -q "$REPO" && git -C "$REPO" checkout -q -b PAY-4-login \
  && git -C "$REPO" -c user.email=t@example.com -c user.name=t commit -q --allow-empty -m init \
  && git -C "$REPO" remote add origin git@github.com:acme/pay.git || { echo "SOME FAILED: could not make a test repository"; exit 1; }

# ════ 1. The plugin's files, as Codex reads them ════
"$PY" - "$P" "$here" <<'EOF' || fail=1
import json, os, re, sys
P, root = sys.argv[1], sys.argv[2]
bad = []
def ok(m): print("ok   " + m)
def need(c, m):
    if c: ok(m)
    else: print("FAIL " + m); bad.append(m)
def load(p):
    with open(p) as f: return json.load(f)
man = load(os.path.join(P, ".codex-plugin/plugin.json"))
mcp = load(os.path.join(P, ".mcp.json"))
hooks = load(os.path.join(P, "hooks/hooks.json"))
mk = load(os.path.join(root, ".agents/plugins/marketplace.json"))
ok("plugin.json, .mcp.json, hooks.json and .agents/plugins/marketplace.json are valid JSON")
# Codex reads .codex-plugin/plugin.json as the "legacy" format, which loads hooks; a root plugin.json would make it an
# Agent Plugins manifest, whose hooks Codex skips (codex-rs/core-plugins/src/loader.rs).
need(not os.path.exists(os.path.join(P, "plugin.json")), "no root plugin.json in the plugin (it would turn its hooks off)")
need(man.get("name") == "seamtrail", "manifest name is seamtrail (plugin seamtrail@seamtrail)")
for key in ("skills", "mcpServers", "hooks"):
    v = man.get(key, "")
    path = os.path.normpath(os.path.join(P, v))
    need(isinstance(v, str) and v.startswith("./") and ".." not in v.split("/") and path.startswith(P) and os.path.exists(path),
         "manifest %s path %r starts with ./ and exists inside the plugin" % (key, v))
srv = mcp.get("mcpServers", {}).get("seamtrail", {})
need(srv.get("type") == "streamable-http" and srv.get("url") == "https://mcp.seamtrail.com/mcp",
     ".mcp.json: server seamtrail, streamable HTTP, https://mcp.seamtrail.com/mcp")
need(srv.get("bearer_token_env_var") == "SEAMTRAIL_TOKEN", ".mcp.json: the token comes from SEAMTRAIL_TOKEN (bearer_token_env_var)")
need(set(srv) <= {"type", "url", "bearer_token_env_var"}, ".mcp.json: only keys Codex knows (snake_case, no 'headers')")
# hooks.json: Codex's HooksFile takes only description and hooks (deny_unknown_fields).
need(set(hooks) <= {"description", "hooks"}, "hooks.json: top level is only description and hooks")
events = {"SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "Stop"}
need(set(hooks["hooks"]) == events, "hooks.json: the five Codex events the plugin uses")
cmd_re = re.compile(r'^sh "\$\{PLUGIN_ROOT\}/scripts/([a-z]+\.sh)"( (person|agent|change))?$')
handlers_ok = True
for ev, groups in hooks["hooks"].items():
    for g in groups:
        if not set(g) <= {"matcher", "hooks"}: handlers_ok = False
        if ev in ("UserPromptSubmit", "Stop", "SessionStart") and "matcher" in g: handlers_ok = False
        for h in g["hooks"]:
            if h.get("type") != "command" or not set(h) <= {"type", "command", "timeout", "statusMessage", "additionalContextLimit"}:
                handlers_ok = False
            m = cmd_re.match(h.get("command", ""))
            if not m or not os.path.isfile(os.path.join(P, "scripts", m.group(1))): handlers_ok = False
            if not (isinstance(h.get("timeout"), int) and 1 <= h["timeout"] <= 30): handlers_ok = False
need(handlers_ok, "hooks.json: every handler is a command hook running an existing script with sh, timeout 1–30 s")
need(hooks["hooks"]["SessionStart"][0]["hooks"][0].get("additionalContextLimit", 0) >= 3000,
     "hooks.json: the chat-start context may be longer than Codex's 2,500-token default (SeamTrail sends up to ~9,000 characters)")
# Matchers: Codex treats a pattern of only letters, digits, _ and | as exact names, anything else as a regex searched
# anywhere in the tool name (codex-rs/hooks/src/engine/matcher.rs) — Python's re.search behaves the same for these.
def matches(m, tool):
    if m in (None, "", "*"): return True
    if re.fullmatch(r"[A-Za-z0-9_|]+", m): return tool in m.split("|")
    return re.search(m, tool) is not None
pre = hooks["hooks"]["PreToolUse"][0]["matcher"]
need(all(matches(pre, t) for t in ["mcp__seamtrail__remember", "mcp__SeamTrail__project_context", "mcp__seamtrail_prod__search"])
     and not any(matches(pre, t) for t in ["mcp__filesystem__read_file", "mcp__notes__seamtrail_lookup", "Bash", "apply_patch", "mcp__memory__remember"]),
     "PreToolUse matcher: SeamTrail servers' tools only (any case), never another server's")
post = {g["hooks"][0]["command"].split("/scripts/")[1]: g["matcher"] for g in hooks["hooks"]["PostToolUse"]}
sv, ch, pk = post['saved.sh"'], post['saved.sh" change'], post['picked.sh"']
want = {
    "mcp__seamtrail__remember": (1, 0, 0), "mcp__seamtrail__resolve": (1, 0, 0), "mcp__seamtrail__settle_question": (1, 0, 0),
    "mcp__SeamTrail__widen_memory": (1, 0, 0), "mcp__seamtrail__ask_seamtrail": (0, 1, 0), "mcp__seamtrail__undo_change": (0, 1, 0),
    "mcp__seamtrail__set_chat_project": (0, 0, 1), "mcp__seamtrail__search_memory": (0, 0, 0), "mcp__memory__remember": (0, 0, 0),
    "mcp__seamtrail__remember_all": (0, 0, 0),
}
need(all((matches(sv, t), matches(ch, t), matches(pk, t)) == tuple(bool(x) for x in w) for t, w in want.items()),
     "PostToolUse matchers: saved after remember/resolve/settle_question/widen_memory, 'change' after ask_seamtrail/undo_change, picked after set_chat_project — on SeamTrail servers only")
# The repository's marketplace (Codex reads .agents/plugins/marketplace.json before .claude-plugin/marketplace.json).
e = mk["plugins"][0]
need(mk.get("name") == "seamtrail" and e.get("name") == man.get("name"), "marketplace seamtrail lists the plugin by its manifest name")
src = e.get("source", {})
need(src.get("source") == "local" and src.get("path") == "./plugins/seamtrail-codex"
     and os.path.isfile(os.path.join(root, src["path"], ".codex-plugin/plugin.json")),
     "marketplace source ./plugins/seamtrail-codex holds .codex-plugin/plugin.json")
need(e.get("policy", {}).get("installation") == "AVAILABLE" and e.get("category"), "marketplace entry has a policy and a category")
skill = open(os.path.join(P, "skills/seamtrail/SKILL.md")).read()
fm = re.match(r"^---\nname: seamtrail\ndescription: (.+)\n---\n", skill)
need(bool(fm) and len(fm.group(1)) <= 1024, "skills/seamtrail/SKILL.md has name and description front matter")
sys.exit(1 if bad else 0)
EOF

# ════ 2. Each script, under every POSIX shell here (macOS sh is bash; Linux sh is often dash) ════
SHELLS=/bin/sh
[ -x /bin/dash ] && SHELLS="$SHELLS /bin/dash"
for SH in $SHELLS; do
  echo "── scripts under $SH"
  for f in "$P"/scripts/*.sh; do $SH -n "$f" || bad "$SH -n $(basename "$f")"; done
  ok "every script parses ($SH -n)"

  # ── start.sh
  D="$W/data-start"; rm -rf "$D"            # Codex does not create the plugin's data folder: the script must
  : > "$FAKE_LOG"
  out=$(cd "$W" && start_in "$REPO" startup | SEAMTRAIL_TOKEN=tok-123 PLUGIN_DATA="$D" FAKE_PROJECT="$PID" FAKE_NAME="Pay ${BS}u2014 web" \
    FAKE_BODY='SeamTrail is your team'"'"'s shared memory of its projects. This folder works on the project "Pay".' $SH "$P/scripts/start.sh")
  check "start: SeamTrail's text goes to Codex as it is (plain text = developer context)" "$out" 'SeamTrail is your team'"'"'s shared memory of its projects. This folder works on the project "Pay".'
  if sent "https://mcp.seamtrail.com/mcp/hook/start" && sent "Authorization: Bearer tok-123" && sent "assistant=codex" \
    && sent "chat=$S" && sent "folder=$REPO" && sent "remote=git@github.com:acme/pay.git" && sent "branch=PAY-4-login"; then
    ok "start: registers the chat — assistant=codex, chat id, folder (from the input's cwd), git remote and branch, token"
  else bad "start: what was sent: $(tr '\n' ' ' < "$FAKE_LOG")"; fi
  if grep -q '^chatName=' "$FAKE_LOG"; then bad "start: sends a chat name Codex does not give"; else ok "start: no chat name (Codex gives none)"; fi
  printf '%s\nPay %su2014 web\n' "$PID" "$BS" > "$W/want-project"
  if cmp -s "$D/project-$S" "$W/want-project"; then ok "start: keeps the chat's project (id and name) in the data folder it made"; else bad "start: project file [$(cat "$D/project-$S" 2>/dev/null)]"; fi

  : > "$D/saved-$S"; : > "$FAKE_LOG"
  out=$(start_in "$REPO" resume | PLUGIN_DATA="$D" $SH "$P/scripts/start.sh")
  if [ -z "$out" ] && [ ! -s "$FAKE_LOG" ] && [ ! -f "$D/saved-$S" ] && [ ! -f "$D/project-$S" ]; then
    ok "start: no SEAMTRAIL_TOKEN → nothing sent, nothing said, the chat starts clean"
  else bad "start without a token: out [$out], sent [$(cat "$FAKE_LOG")]"; fi

  : > "$FAKE_LOG"
  out=$(start_in "$REPO" | SEAMTRAIL_TOKEN=t SEAMTRAIL_URL=https://st.example.com/mcp/ PLUGIN_DATA="$D" FAKE_PROJECT=ask FAKE_NAME= FAKE_BODY='SeamTrail is…' $SH "$P/scripts/start.sh")
  printf 'ask\n\n' > "$W/want-project"
  if sent "https://st.example.com/mcp/hook/start" && cmp -s "$D/project-$S" "$W/want-project"; then
    ok "start: SEAMTRAIL_URL is used; two projects matched → 'ask' kept"
  else bad "start with SEAMTRAIL_URL / ask: [$(tr '\n' ' ' < "$FAKE_LOG")] [$(cat "$D/project-$S" 2>/dev/null)]"; fi

  rm -f "$D/project-$S"
  out=$(start_in "$REPO" | SEAMTRAIL_TOKEN=t PLUGIN_DATA="$D" FAKE_FAIL=1 FAKE_PROJECT="$PID" FAKE_BODY='x' $SH "$P/scripts/start.sh"); rc=$?
  if [ $rc = 0 ] && [ -z "$out" ] && [ ! -f "$D/project-$S" ]; then ok "start: SeamTrail unreachable → silent, exit 0"; else bad "start on failure: rc $rc out [$out]"; fi

  X="$W/xdg"; rm -rf "$X"
  out=$(start_in "$REPO" | SEAMTRAIL_TOKEN=t XDG_STATE_HOME="$X" FAKE_PROJECT="$PID" FAKE_NAME=Pay FAKE_BODY='x' $SH "$P/scripts/start.sh")
  if [ -f "$X/seamtrail/codex/project-$S" ]; then ok "start: without PLUGIN_DATA, state goes to \$XDG_STATE_HOME/seamtrail/codex"; else bad "start: XDG fallback"; fi

  # ── message.sh
  : > "$FAKE_LOG"
  out=$(prompt_in 'Can you look at PAY-4 and WEB-12?\nSee also PAY-4; he said \"OPS-77\" too' ',"agent_id":null' \
    | SEAMTRAIL_TOKEN=tok-123 FAKE_BODY='SeamTrail, for this message (project "Pay"): PAY-4 is blocked.' $SH "$P/scripts/message.sh")
  check "message: SeamTrail's text goes to Codex with the message" "$out" 'SeamTrail, for this message (project "Pay"): PAY-4 is blocked.'
  if sent "https://mcp.seamtrail.com/mcp/hook/message" && sent "chat=$S" && sent "tickets=OPS-77,PAY-4,WEB-12"; then
    ok "message: sends the chat id and the message's ticket numbers"
  else bad "message: what was sent: $(tr '\n' ' ' < "$FAKE_LOG")"; fi
  if grep -qi 'look at\|see also\|he said' "$FAKE_LOG"; then bad "message: words of the message were sent"; else ok "message: never the message's words"; fi

  : > "$FAKE_LOG"
  out=$(printf '{"session_id":"%s","turn_id":"t1","hook_event_name":"UserPromptSubmit","prompt":"fix PAY-4","cwd":"/work/OPS-9-branch","model":"gpt-5.5-codex"}' "$S" \
    | SEAMTRAIL_TOKEN=t FAKE_BODY= $SH "$P/scripts/message.sh")
  if sent "tickets=PAY-4" && [ -z "$out" ]; then ok "message: only the prompt's tickets, not other fields after it; nothing to tell → nothing added"; else bad "message: [$(tr '\n' ' ' < "$FAKE_LOG")] [$out]"; fi

  : > "$FAKE_LOG"
  prompt_in 'A-1 AB-1 CD-2 EF-3 GH-4 IJ-5 KL-6' | SEAMTRAIL_TOKEN=t FAKE_BODY= $SH "$P/scripts/message.sh" >/dev/null
  if sent "tickets=AB-1,CD-2,EF-3,GH-4,IJ-5"; then ok "message: at most five tickets"; else bad "message five: $(tr '\n' ' ' < "$FAKE_LOG")"; fi

  : > "$FAKE_LOG"
  out=$(prompt_in 'PAY-4' | FAKE_BODY=x $SH "$P/scripts/message.sh")
  out2=$(prompt_in 'PAY-4' ',"agent_id":"019a7c3f-0000-7000-8000-000000000001","agent_type":"worker"' | SEAMTRAIL_TOKEN=t FAKE_BODY=x $SH "$P/scripts/message.sh")
  if [ -z "$out$out2" ] && [ ! -s "$FAKE_LOG" ]; then ok "message: no token, or a subagent's input → nothing sent, nothing added"; else bad "message no token / subagent: [$out] [$out2]"; fi

  # ── tickets.sh and guard.sh, with each JSON tool (jq, node, python3) and with none
  for tool in jq node python3 none; do
    B="$W/box-$tool"
    [ "$tool" = none ] || [ -e "$B/$tool" ] || { echo "skip $tool (not installed)"; continue; }
    D="$W/data-$tool"; rm -rf "$D"
    prompt_in 'Look at PAY-4 and WEB-12' | PATH="$B" PLUGIN_DATA="$D" $SH "$P/scripts/tickets.sh" person
    stop_in false 'Moved PAY-4; WEB-12 waits on API-3.' | PATH="$B" PLUGIN_DATA="$D" $SH "$P/scripts/tickets.sh" agent
    for i in 1 2 3; do prompt_in "message $i about OLD-$i" | PATH="$B" PLUGIN_DATA="$D" $SH "$P/scripts/tickets.sh" person; done
    for i in 1 2 3 3; do stop_in false "reply $i on AGT-$i" | PATH="$B" PLUGIN_DATA="$D" $SH "$P/scripts/tickets.sh" agent; done
    prompt_in 'TASK-1' ',"agent_id":"019a7c3f-0000-7000-8000-000000000001"' | PATH="$B" PLUGIN_DATA="$D" $SH "$P/scripts/tickets.sh" person
    if [ "$tool" = none ]; then
      if [ ! -s "$D/tickets-$S.jsonl" ]; then ok "tickets ($tool): no JSON tool → keeps nothing"; else bad "tickets ($tool) kept something"; fi
    else
      pyck "tickets ($tool): the last 3 messages each way, numbers only; a reply seen twice counts once; a subagent's input is skipped" \
        "$("$PY" -c 'import json,sys; print(json.dumps([json.loads(l) for l in open(sys.argv[1]) if l.strip()]))' "$D/tickets-$S.jsonl")" '
rows = [(r["r"], r["k"]) for r in d]
assert rows == [("person", ["OLD-1"]), ("person", ["OLD-2"]), ("person", ["OLD-3"]),
                ("agent", ["AGT-1"]), ("agent", ["AGT-2"]), ("agent", ["AGT-3"])], rows
assert all(set(r) == {"r", "n", "k"} for r in d), d'
    fi

    # The guard, with tickets kept: a SeamTrail tool gets the chat id and the ticket numbers.
    printf '{"r":"person","n":24,"k":["WEB-12","PAY-4"]}\n{"r":"agent","n":30,"k":["PAY-4"]}\n' > "$D/tickets-$S.jsonl"
    out=$(pre_in mcp__seamtrail__remember '{"kind":"decision","text":"Chose Postgres for audit logs","chatId":"made-up"}' \
      | PATH="$B" PLUGIN_DATA="$D" $SH "$P/scripts/guard.sh")
    if [ "$tool" = none ]; then
      check "guard ($tool): no JSON tool → the call goes on as it is" "$out" ""
      continue
    fi
    pyck "guard ($tool): adds chatId (the session id) and chatTickets, in the only shape Codex takes (allow + updatedInput)" "$out" "
assert set(d) == {'hookSpecificOutput'}, d
h = d['hookSpecificOutput']
assert set(h) == {'hookEventName', 'permissionDecision', 'updatedInput'}, h
assert h['hookEventName'] == 'PreToolUse' and h['permissionDecision'] == 'allow', h
assert h['updatedInput'] == {'kind': 'decision', 'text': 'Chose Postgres for audit logs', 'chatId': '$S', 'chatTickets': 'PAY-4,WEB-12'}, h"
    rm -f "$D/tickets-$S.jsonl"
    out=$(pre_in mcp__SeamTrail__search_memory '{"query":"audit"}' | PATH="$B" PLUGIN_DATA="$D" $SH "$P/scripts/guard.sh")
    pyck "guard ($tool): a SeamTrail connection the person added (any case) is tagged too; no tickets → no chatTickets" "$out" "
assert d['hookSpecificOutput']['updatedInput'] == {'query': 'audit', 'chatId': '$S'}, d"
    out=$(pre_in mcp__seamtrail__list_projects 'null' | PATH="$B" PLUGIN_DATA="$D" $SH "$P/scripts/guard.sh")
    pyck "guard ($tool): a call with no arguments gets just the chat id" "$out" "
assert d['hookSpecificOutput']['updatedInput'] == {'chatId': '$S'}, d"
    out=$(pre_in mcp__seamtrail__project_context '{"projectId":"p"}' ',"agent_id":"019a7c3f-0000-7000-8000-000000000001","agent_type":"worker"' | PATH="$B" PLUGIN_DATA="$D" $SH "$P/scripts/guard.sh")
    pyck "guard ($tool): a subagent's SeamTrail call carries its parent chat's id" "$out" "
assert d['hookSpecificOutput']['updatedInput'] == {'projectId': 'p', 'chatId': '$S'}, d"
    o1=$(pre_in mcp__filesystem__read_file '{"path":"/etc/hosts"}' | PATH="$B" PLUGIN_DATA="$D" $SH "$P/scripts/guard.sh")
    o2=$(pre_in mcp__notes__seamtrail_lookup '{"q":"x"}' | PATH="$B" PLUGIN_DATA="$D" $SH "$P/scripts/guard.sh")
    o3=$(pre_in mcp__seamtrail__remember '"not json"' | PATH="$B" PLUGIN_DATA="$D" $SH "$P/scripts/guard.sh")
    o4=$(printf '{"hook_event_name":"PreToolUse","tool_name":"mcp__seamtrail__remember","tool_input":{}}' | PATH="$B" PLUGIN_DATA="$D" $SH "$P/scripts/guard.sh")
    check "guard ($tool): never another server's tools, odd arguments or a call without a session" "$o1$o2$o3$o4" ""
  done

  # ── saved.sh: the same answers as the Claude Code plugin's, on Codex's PostToolUse input
  saved_case() { # name, tool, tool_response JSON, mode, wanted (saved|not)
    rm -rf "$W/sv-c" "$W/sv-t"; mkdir -p "$W/sv-t"
    in=$(post_in "$2" '{"question":"x"}' "$3")
    printf '%s' "$in" | PLUGIN_DATA="$W/sv-c" $SH "$P/scripts/saved.sh" $4
    printf '%s' "$in" | CLAUDE_PLUGIN_DATA="$W/sv-t" sh "$T/scripts/saved.sh" $4
    if [ -f "$W/sv-c/saved-$S" ]; then got=saved; else got=not; fi
    if [ -f "$W/sv-t/saved-$S" ]; then tg=saved; else tg=not; fi
    if [ "$got" = "$5" ] && [ "$tg" = "$5" ]; then ok "saved: $1 → $got (same as the Claude Code plugin)"; else bad "saved: $1 → $got, template $tg, wanted $5"; fi
  }
  saved_case "remember" mcp__seamtrail__remember '{"content":[{"type":"text","text":"{\"memoryId\":\"m1\",\"kind\":\"fact\"}"}]}' "" saved
  saved_case "resolve" mcp__seamtrail__resolve '{"content":[{"type":"text","text":"Resolved."}]}' "" saved
  saved_case "ask_seamtrail, a question only" mcp__seamtrail__ask_seamtrail '{"content":[{"type":"text","text":"{\"answer\":\"No ticket found\",\"checked\":[\"search_jira\"]}"}]}' change not
  saved_case "ask_seamtrail, a real change (content text)" mcp__seamtrail__ask_seamtrail '{"content":[{"type":"text","text":"{\"answer\":\"Done: moved\",\"did\":[{\"what\":\"move ticket\",\"done\":true,\"verified\":true}]}"}]}' change saved
  saved_case "ask_seamtrail, a real change (structuredContent)" mcp__seamtrail__ask_seamtrail '{"content":[],"structuredContent":{"did":[{"what":"move","done":true}]}}' change saved
  saved_case "ask_seamtrail, a real change (plain text reply)" mcp__seamtrail__ask_seamtrail '"{\"did\":[{\"what\":\"move\",\"done\":true}]}"' change saved
  saved_case "ask_seamtrail, a change that failed" mcp__seamtrail__ask_seamtrail '{"content":[{"type":"text","text":"{\"answer\":\"Not done\",\"did\":[{\"what\":\"move\",\"done\":false,\"error\":\"Jira refused\"}]}"}]}' change not
  saved_case "ask_seamtrail, a read that happens to hold done:true" mcp__seamtrail__ask_seamtrail '{"content":[{"type":"text","text":"{\"tool\":\"promotion_rules\",\"result\":{\"checklist\":[{\"label\":\"flag\",\"done\":true}]}}"}]}' change not
  saved_case "undo_change" mcp__seamtrail__undo_change '{"content":[{"type":"text","text":"Undone — reading it back confirms it."}]}' change saved
  saved_case "undo_change that failed" mcp__seamtrail__undo_change '{"content":[{"type":"text","text":"That is not an undo handle"}],"isError":true}' change not

  # ── picked.sh
  D="$W/data-picked"; rm -rf "$D"
  post_in mcp__seamtrail__set_chat_project "{\"projectId\":\"$PID\",\"chatId\":\"$S\"}" '{"content":[{"type":"text","text":"Set."}]}' | PLUGIN_DATA="$D" $SH "$P/scripts/picked.sh"
  printf '%s\n\n' "$PID" > "$W/want-project"
  if cmp -s "$D/project-$S" "$W/want-project"; then ok "picked: the picked project is kept (by id) for the turn-end check"; else bad "picked: [$(cat "$D/project-$S" 2>/dev/null)]"; fi
  post_in mcp__seamtrail__set_chat_project '{"projectId":"0b1c2d3e-0000-4000-8000-000000000000"}' '{"content":[{"type":"text","text":"Not your project"}],"isError":true}' | PLUGIN_DATA="$D" $SH "$P/scripts/picked.sh"
  if cmp -s "$D/project-$S" "$W/want-project"; then ok "picked: a refused pick changes nothing"; else bad "picked after a refusal: [$(cat "$D/project-$S")]"; fi
  post_in mcp__seamtrail__set_chat_project '{"none":true}' '{"content":[{"type":"text","text":"No project for this chat."}]}' | PLUGIN_DATA="$D" $SH "$P/scripts/picked.sh"
  if [ ! -f "$D/project-$S" ]; then ok "picked: \"No project\" → the turn-end check stays quiet"; else bad "picked no project"; fi

  # ── stop.sh: the same words as the Claude Code plugin's, byte for byte, and a reply Codex takes
  stop_case() { # name, project id (- for none), project name, saved (yes|no), stop_hook_active, wanted (ask|quiet)
    for d in "$W/st-c" "$W/st-t"; do
      rm -rf "$d"; mkdir -p "$d"
      [ "$2" = - ] || printf '%s\n%s\n' "$2" "$3" > "$d/project-$S"
      [ "$4" = yes ] && : > "$d/saved-$S"
    done
    in=$(stop_in "$5" 'Done with PAY-4.')
    out=$(printf '%s' "$in" | PLUGIN_DATA="$W/st-c" $SH "$P/scripts/stop.sh")
    tout=$(printf '%s' "$in" | CLAUDE_PLUGIN_DATA="$W/st-t" sh "$T/scripts/stop.sh")
    if [ "$out" != "$tout" ]; then bad "stop: $1 — differs from the Claude Code plugin: [$out] vs [$tout]"; return; fi
    if [ -f "$W/st-c/saved-$S" ] || [ -f "$W/st-t/saved-$S" ]; then bad "stop: $1 — the saved marker was not cleared"; return; fi
    if [ "$6" = quiet ]; then check "stop: $1 → quiet (same as the Claude Code plugin)" "$out" ""; return; fi
    pyck "stop: $1 → asks once, same words as the Claude Code plugin, as {decision: block, reason}" "$out" "
assert set(d) == {'decision', 'reason'} and d['decision'] == 'block' and d['reason'].strip(), d
assert d['reason'].startswith('SeamTrail: nothing was saved this turn.'), d
$7"
  }
  stop_case "a picked project with its name" "$PID" "Caf${BS}u00e9 ${BS}\"Pay${BS}\" ${BS}u2014 web" no false ask "
assert 'projectId $PID (the project “Café \"Pay\" — web”)' in d['reason'], d['reason']
assert 'This chat saves only into that project: if something belongs to another project, tell your person instead' in d['reason']"
  stop_case "a project picked during the chat (id only)" "$PID" '' no false ask "
assert 'projectId $PID: one note per thing' in d['reason'], d['reason']
assert 'decision = a choice a person made' in d['reason'] and 'your own build steps go here' in d['reason'], d['reason']"
  stop_case "two projects matched (older SeamTrail)" ask '' no false ask "
assert 'more than one SeamTrail project' in d['reason'], d['reason']"
  stop_case "saved this turn" "$PID" Pay yes false quiet
  stop_case "asked once already (stop_hook_active)" "$PID" Pay no true quiet
  stop_case "no project" - '' no false quiet
done

# ════ 3. A Codex chat, every hook run from hooks.json the way Codex runs it ════
# The command lines Codex would run for an event (and tool), ${PLUGIN_ROOT} replaced as Codex does before the shell.
cmds() {
  "$PY" -c '
import json, re, sys
path, event, tool, root = sys.argv[1:5]
for g in json.load(open(path))["hooks"].get(event, []):
    m = g.get("matcher")
    if event in ("UserPromptSubmit", "Stop") or m in (None, "", "*"): hit = True
    elif re.fullmatch(r"[A-Za-z0-9_|]+", m): hit = tool in m.split("|")
    else: hit = re.search(m, tool) is not None
    if hit:
        for h in g["hooks"]:
            print(h["command"].replace("${PLUGIN_ROOT}", root))
' "$P/hooks/hooks.json" "$1" "${2:-}" "$P"
}
fire() { # shell, event, tool, input → the stdout of every matching hook, run in the session's folder
  cmds "$2" "$3" | while IFS= read -r c; do
    printf '%s' "$4" | (cd "$REPO" && PLUGIN_ROOT="$P" PLUGIN_DATA="$E2E" CLAUDE_PLUGIN_ROOT="$P" CLAUDE_PLUGIN_DATA="$E2E" "$1" -c "$c")
  done
}
SH_LINES=/bin/sh
[ -x /bin/zsh ] && SH_LINES="$SH_LINES /bin/zsh"
for L in $SH_LINES; do
  echo "── a Codex chat, hook command lines run by $L"
  E2E="$W/e2e-$(basename "$L")"; rm -rf "$E2E"; : > "$FAKE_LOG"
  export SEAMTRAIL_TOKEN=tok-e2e FAKE_PROJECT="$PID" FAKE_NAME=Pay
  FAKE_BODY='SeamTrail is your team'"'"'s shared memory of its projects. Project "Pay": where it stands…'; export FAKE_BODY
  out=$(fire "$L" SessionStart "" "$(start_in "$REPO" startup)")
  check "e2e: chat start hands Codex the project's context" "$out" "$FAKE_BODY"
  FAKE_BODY='SeamTrail, for this message (project "Pay"): PAY-4 moved to review.'
  out=$(fire "$L" UserPromptSubmit "" "$(prompt_in 'Let us finish PAY-4 today')")
  check "e2e: the message gets what is new on its tickets" "$out" "$FAKE_BODY"
  out=$(fire "$L" PreToolUse mcp__seamtrail__remember "$(pre_in mcp__seamtrail__remember '{"kind":"decision","text":"PAY-4 ships behind a flag"}')")
  pyck "e2e: the remember call carries the chat id and the message's ticket" "$out" "
assert d['hookSpecificOutput']['updatedInput'] == {'kind': 'decision', 'text': 'PAY-4 ships behind a flag', 'chatId': '$S', 'chatTickets': 'PAY-4'}, d"
  out=$(fire "$L" PreToolUse mcp__filesystem__read_file "$(pre_in mcp__filesystem__read_file '{"path":"x"}')")
  check "e2e: another server's tool runs no SeamTrail hook" "$out" ""
  out=$(fire "$L" PostToolUse mcp__seamtrail__remember "$(post_in mcp__seamtrail__remember '{"kind":"decision"}' '{"content":[{"type":"text","text":"{\"memoryId\":\"m1\"}"}]}')")
  if [ -z "$out" ] && [ -f "$E2E/saved-$S" ]; then ok "e2e: remember marks the turn saved"; else bad "e2e: saved marker after remember"; fi
  out=$(fire "$L" Stop "" "$(stop_in false 'Saved the decision on PAY-4; WEB-7 next.')")
  if [ -z "$out" ] && [ ! -f "$E2E/saved-$S" ]; then ok "e2e: turn end after a save → quiet, next turn starts clean"; else bad "e2e: stop after save [$out]"; fi
  FAKE_BODY=
  out=$(fire "$L" UserPromptSubmit "" "$(prompt_in 'thanks, what next?')")
  check "e2e: nothing new → nothing added to the message" "$out" ""
  out=$(fire "$L" Stop "" "$(stop_in false 'Next is WEB-7.')")
  pyck "e2e: turn end with nothing saved → one reminder naming the chat's project" "$out" "
assert d['decision'] == 'block' and 'projectId $PID (the project “Pay”)' in d['reason'], d"
  fire "$L" PostToolUse mcp__seamtrail__remember "$(post_in mcp__seamtrail__remember '{}' '{"content":[{"type":"text","text":"ok"}]}')" >/dev/null
  out=$(fire "$L" Stop "" "$(stop_in true 'Saved.')")
  if [ -z "$out" ] && [ ! -f "$E2E/saved-$S" ]; then ok "e2e: after the reminder (stop_hook_active) → quiet"; else bad "e2e: second stop [$out]"; fi
  out=$(fire "$L" PreToolUse mcp__seamtrail__ask_seamtrail "$(pre_in mcp__seamtrail__ask_seamtrail '{"question":"move WEB-7"}')")
  pyck "e2e: the agent's own reply's tickets go along too (last 3 replies)" "$out" "
assert d['hookSpecificOutput']['updatedInput']['chatTickets'] == 'PAY-4,WEB-7', d"
  out=$(fire "$L" PostToolUse mcp__seamtrail__set_chat_project "$(post_in mcp__seamtrail__set_chat_project '{"none":true}' '{"content":[{"type":"text","text":"No project."}]}')")
  out=$(fire "$L" Stop "" "$(stop_in false 'ok')")
  check "e2e: after \"No project\" is picked → the turn end never asks" "$out" ""
  : > "$E2E/saved-$S"
  FAKE_BODY=x
  fire "$L" SessionStart "" "$(start_in "$REPO" resume)" >/dev/null
  if [ ! -f "$E2E/saved-$S" ] && [ -f "$E2E/project-$S" ]; then ok "e2e: a resumed chat starts clean and gets its project again"; else bad "e2e: resume"; fi
  if grep -qi 'finish PAY-4 today\|thanks, what next\|ships behind a flag\|Saved the decision\|Next is' "$FAKE_LOG"; then
    bad "e2e: conversation text was sent to SeamTrail"
  else ok "e2e: across the chat, only ids, ticket numbers, folder, remote and branch were sent — never the conversation"; fi
  unset SEAMTRAIL_TOKEN FAKE_PROJECT FAKE_NAME FAKE_BODY
done

[ $fail = 0 ] && echo "ALL PASSED" || echo "SOME FAILED"
exit $fail
