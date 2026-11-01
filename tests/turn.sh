#!/bin/sh
# SEAM-233 · one row per message (founder 2026-10-25: "build the plugin side on a branch"): message.sh gives each
# message an id and keeps it on this computer; guard.sh adds it to every SeamTrail call; turn.sh sends, once per message
# at its first stop, a cut of what was asked and of Claude's final reply — cleaned on this computer — with the ticket
# numbers, in the background so the chat never waits. Needs python3. No network: curl is a stand-in that logs what it
# was given.
here=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
S="$here/plugins/seamtrail/scripts"
H="$here/plugins/seamtrail/hooks/hooks.json"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
export S H T
python3 -I - <<'PY'
import json, os, re, subprocess, time
S, H, T = os.environ["S"], os.environ["H"], os.environ["T"]
fail = 0
def check(label, cond, info=""):
    global fail
    print(("ok   " if cond else "FAIL ") + label + ("" if cond else f" — {info}"))
    fail |= not cond

def which(t):
    r = subprocess.run(["sh", "-c", f"command -v {t}"], capture_output=True, text=True).stdout.strip()
    return r if r.startswith("/") else None

# A stand-in curl: after $CURL_SLEEP seconds, logs its arguments and the body it was given, writes "news" to its -o
# file, and prints $POST_CODE (200 unless set) when asked for the status.
BIN = f"{T}/bin"
os.makedirs(BIN)
with open(f"{BIN}/curl", "w") as f:
    f.write(r'''#!/bin/sh
[ -n "$CURL_SLEEP" ] && sleep "$CURL_SLEEP"
{ printf 'ARGS:'; for a in "$@"; do printf ' %s' "$a"; done; printf '\n'; } >> "$CURL_LOG"
prev=""; out=""; code=""
for a in "$@"; do
  if [ "$prev" = "--data-binary" ]; then
    printf 'BODY:' >> "$CURL_LOG"
    if [ "$a" = "@-" ]; then cat >> "$CURL_LOG"; else cat "${a#@}" >> "$CURL_LOG"; fi
    printf '\n' >> "$CURL_LOG"
  fi
  [ "$prev" = "-o" ] && out="$a"
  [ "$prev" = "-w" ] && code=1
  prev="$a"
done
[ -n "$out" ] && [ "$out" != /dev/null ] && printf 'news' > "$out"
[ -n "$code" ] && printf '%s' "${POST_CODE:-200}"
exit 0
''')
os.chmod(f"{BIN}/curl", 0o755)

BASICS = ["sh", "cat", "grep", "sed", "head", "dirname", "uname", "xcode-select", "printf", "mktemp", "rm", "tr",
          "find", "mkdir", "sort", "paste", "sleep", "uuidgen"]
def path_with(*tools):
    d = os.path.join(T, "path-" + "-".join(tools or ("none",)))
    if not os.path.isdir(d):
        os.makedirs(d)
        for t in BASICS + list(tools):
            w = which(t)
            if w and not os.path.exists(os.path.join(d, t)):
                os.symlink(w, os.path.join(d, t))
        os.symlink(f"{BIN}/curl", os.path.join(d, "curl"))
    return d

DATA, LOG = f"{T}/data", f"{T}/curl.log"
def run(script, payload, path, **kw):
    env = {"PATH": path, "HOME": T, "TMPDIR": T, "CLAUDE_PLUGIN_DATA": DATA, "CURL_LOG": LOG, "SEAMTRAIL_TOKEN": "tok-1"}
    for k, v in kw.items():
        if v is None:
            env.pop(k, None)
        else:
            env[k] = v
    t0 = time.time()
    p = subprocess.run(["sh", f"{S}/{script}"], input=json.dumps(payload), capture_output=True, text=True, env=env,
                       timeout=30)
    return p.stdout, time.time() - t0
def reset():
    open(LOG, "w").close()
def log():
    try:
        return open(LOG).read()
    except FileNotFoundError:
        return ""
def calls(route):
    out = []
    for line in log().splitlines():
        if line.startswith("ARGS:"):
            out.append({"args": line[5:], "body": None})
        elif line.startswith("BODY:") and out:
            try:
                out[-1]["body"] = json.loads(line[5:])
            except ValueError:
                pass
    return [c for c in out if route in c["args"] and c["body"] is not None]
def wait_turns(n, secs=10):
    end = time.time() + secs
    while time.time() < end:
        if len(calls("/hook/turn")) >= n:
            return True
        time.sleep(0.1)
    return False
def stop(chat, reply, path, again=False, **kw):
    return run("turn.sh", {"session_id": chat, "hook_event_name": "Stop", "stop_hook_active": again,
                           "last_assistant_message": reply}, path, **kw)
def turn_file(chat):
    try:
        return json.load(open(f"{DATA}/turn-{chat}.json"))
    except (OSError, ValueError):
        return {}

SECRET = "gh" + "p_abcdefghijklmnopqrstuvwxyz0123456789"  # two pieces: no token-shaped string in this file
tools = [t for t in ("node", "python3") if which(t)]
check("at least one of node and python3 runs here", len(tools) >= 1)

for name in tools:
    path, chat = path_with(name), f"chat-{name}-0001"
    reset()
    out, _ = run("message.sh", {"session_id": chat, "prompt": f"fix the refund window in PAY-4, token {SECRET}"}, path)
    posts = calls("/hook/message")
    body = posts[0]["body"] if posts else {}
    mid = body.get("messageId", "")
    check(f"{name}: message.sh sends a new message id with the message", bool(re.fullmatch(r"[a-z0-9-]{36}", mid)), json.dumps(body))
    check(f"{name}: message.sh still hands Claude what SeamTrail answered", out == "news", out)
    check(f"{name}: no secret in what message.sh sent", SECRET not in log(), log())
    t = turn_file(chat)
    check(f"{name}: the id and the cleaned hint wait on this computer", t.get("messageId") == mid and "PAY-4" in t.get("hint", "") and SECRET not in json.dumps(t), json.dumps(t))

    g, _ = run("guard.sh", {"session_id": chat, "tool_name": "mcp__plugin_seamtrail_seamtrail__remember", "tool_input": {"content": "x"}}, path)
    ui = json.loads(g)["hookSpecificOutput"]["updatedInput"] if g.strip() else {}
    check(f"guard with {name}: adds the message id beside the chat id", ui.get("messageId") == mid and ui.get("chatId") == chat, json.dumps(ui))

    reply = ("Fixed the refund window bug in PAY-4 and SEAM-233.\n```js\nconst internalThing = connect('prod-db');\n```\n"
             f"Also rotate the key {SECRET}.")
    reset()
    _, took = stop(chat, reply, path, CURL_SLEEP="2")
    check(f"turn.sh with {name}: returns at once; the call goes in the background", took < 1.5, f"{took:.2f}s")
    check(f"turn.sh with {name}: the end call arrives", wait_turns(1), log())
    sent = calls("/hook/turn")
    tb = sent[0]["body"] if sent else {}
    check(f"turn.sh with {name}: to /hook/turn, with the token", bool(sent) and "/hook/turn" in sent[0]["args"] and "Authorization: Bearer tok-1" in sent[0]["args"], log())
    check(f"turn.sh with {name}: chat, message id, asked and did", tb.get("chat") == chat and tb.get("messageId") == mid and "PAY-4" in (tb.get("asked") or "") and (tb.get("did") or "").startswith("Fixed the refund window bug in PAY-4"), json.dumps(tb))
    check(f"turn.sh with {name}: no code, secret or credential leaves", "internalThing" not in log() and SECRET not in log(), log())
    check(f"turn.sh with {name}: the ticket numbers of the message and of the reply", tb.get("tickets") == "PAY-4,SEAM-233", json.dumps(tb))
    time.sleep(0.3)
    check(f"turn.sh with {name}: leaves no file behind", not [f for f in os.listdir(T) if f.startswith("tmp.")], os.listdir(T))

    reset()
    stop(chat, "Nothing new to save.", path, again=True)
    stop(chat, "Again, for the same message.", path)
    time.sleep(0.5)
    check(f"turn.sh with {name}: once per message — a second stop sends nothing", calls("/hook/turn") == [], log())

    run("message.sh", {"session_id": chat, "prompt": "now update the docs"}, path)
    mid2 = turn_file(chat).get("messageId")
    reset()
    stop(chat, "Updated the docs page.", path)
    ok = wait_turns(1)
    check(f"turn.sh with {name}: the next message goes with its own id", ok and calls("/hook/turn")[0]["body"].get("messageId") == mid2 and mid2 != mid, log())

    run("message.sh", {"session_id": chat, "prompt": "write it up"}, path)
    long = "START " + " ".join(f"w{i}" for i in range(800)) + " see https://docs.example.com/spec/42 END"
    reset()
    stop(chat, long, path)
    ok = wait_turns(1)
    did = calls("/hook/turn")[0]["body"].get("did") or "" if ok else ""
    check(f"turn.sh with {name}: a long reply is cut — its start, its end and its links", did.startswith("START w0") and " … " in did and "END" in did and "https://docs.example.com/spec/42" in did and len(did) <= 1500, did[:80])

# node and python3 make the same body from the same message and reply.
if len(tools) == 2:
    bodies = []
    for name in tools:
        chat = "chat-same-0001"
        os.makedirs(DATA, exist_ok=True)
        with open(f"{DATA}/turn-{chat}.json", "w") as f:
            json.dump({"chat": chat, "messageId": "0f8e5c1a-1111-4222-8333-944455556666", "tickets": "PAY-4", "hint": "fix it ✓"}, f)
        if os.path.exists(f"{DATA}/turn-{chat}.sent"):
            os.remove(f"{DATA}/turn-{chat}.sent")
        reset()
        stop(chat, "Done — naïve café ✓ in SEAM-9. password=hunter2", path_with(name))
        wait_turns(1)
        bodies.append(calls("/hook/turn")[0]["body"] if calls("/hook/turn") else None)
    check("node and python3 make the same body", bodies[0] is not None and bodies[0] == bodies[1] and "hunter2" not in json.dumps(bodies[0]), json.dumps(bodies))

# Nothing is sent: no message seen (no turn file), no token, or no node and python3 to clean the reply.
path = path_with(tools[0])
run("message.sh", {"session_id": "chat-token-0001", "prompt": "fix the refund window in PAY-4"}, path)
reset()
stop("chat-never-0001", "Fixed it.", path)
stop("chat-token-0001", "Fixed it.", path, SEAMTRAIL_TOKEN=None)
time.sleep(0.5)
check("nothing sent for a chat with no message seen, or without a token", "/hook/turn" not in log(), log())
stop("chat-token-0001", "Fixed it.", path)
check("... and the same message, with the token, is sent", wait_turns(1), log())
none = path_with()
reset()
out, _ = run("message.sh", {"session_id": "chat-bare-0001", "prompt": "fix the refund window in PAY-4"}, none)
gets = [l for l in log().splitlines() if l.startswith("ARGS:") and " -G " in l + " "]
t = turn_file("chat-bare-0001")
check("without node or python3: no words leave; the id still goes with the chat id and the tickets", "refund window" not in log() and "BODY:" not in log() and bool(gets) and "tickets=PAY-4" in gets[-1] and ("messageId=" + t.get("messageId", "?")) in gets[-1], log())
reset()
stop("chat-bare-0001", "Fixed the refund window in PAY-4.", none)
time.sleep(0.5)
check("without node or python3: the end call sends nothing", "/hook/turn" not in log(), log())
if which("jq"):
    g, _ = run("guard.sh", {"session_id": "chat-bare-0001", "tool_name": "mcp__plugin_seamtrail_seamtrail__remember", "tool_input": {"content": "x"}}, path_with("jq"))
    ui = json.loads(g)["hookSpecificOutput"]["updatedInput"] if g.strip() else {}
    check("guard with only jq: adds the message id beside the chat id", ui.get("messageId") == t.get("messageId") and ui.get("chatId") == "chat-bare-0001", json.dumps(ui))
    with open(f"{DATA}/turn-chat-bare-0001.json", "w") as f:
        f.write("{not json")
    g, _ = run("guard.sh", {"session_id": "chat-bare-0001", "tool_name": "mcp__plugin_seamtrail_seamtrail__remember", "tool_input": {"content": "x"}}, path_with("jq"))
    ui = json.loads(g)["hookSpecificOutput"]["updatedInput"] if g.strip() else {}
    check("guard with only jq: a broken turn file never stops the chat id", ui.get("chatId") == "chat-bare-0001" and "messageId" not in ui, json.dumps(ui))

stops = [h["command"] for e in json.load(open(H))["hooks"]["Stop"] for h in e["hooks"]]
check("hooks.json runs turn.sh at turn end", any(c.endswith("/scripts/turn.sh") for c in stops), json.dumps(stops))
print("ALL PASSED" if not fail else "SOME FAILED")
raise SystemExit(1 if fail else 0)
PY
