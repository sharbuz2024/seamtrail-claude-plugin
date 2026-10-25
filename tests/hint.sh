#!/bin/sh
# SEAM-233 · the search hint the message hook sends (founder 2026-10-24: "just make sure no secrets and credentials"):
# no secret or credential and no code block ever leaves; the words that say what the message is about stay; node
# (hint.js) and python3 (hint.py) give the same hint; message.sh sends it in the body, and without node or python3
# sends no words at all. Needs python3 for the checks. No network: curl is a stand-in that logs what it was given.
here=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
S="$here/plugins/seamtrail/scripts"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
export S T
python3 -I - <<'PY'
import json, os, subprocess, sys
S, T = os.environ["S"], os.environ["T"]
fail = 0
def check(label, cond, info=""):
    global fail
    print(("ok   " if cond else "FAIL ") + label + ("" if cond else f" — {info}"))
    fail |= not cond

def run(cmd, prompt, session="chat-1"):
    p = subprocess.run(cmd + [f"{S}/hint-rules.json"], input=json.dumps({"session_id": session, "prompt": prompt}),
                       capture_output=True, text=True, timeout=20)
    return json.loads(p.stdout) if p.stdout else None

tools = []
if subprocess.run(["sh", "-c", "command -v node"], capture_output=True).returncode == 0:
    tools.append(("node", ["node", f"{S}/hint.js"]))
tools.append(("python3", [sys.executable, "-I", f"{S}/hint.py"]))
check("at least one cleaner runs here", len(tools) >= 1)

# Each fake secret is built from two pieces, so this file never holds a token-shaped string (GitHub's push protection
# reads one as real); the values the cleaner sees are whole.
SECRETS = {
    "AWS key id": "AKIA" + "IOSFODNN7EXAMPLE",
    "AWS secret": "wJalrXUtnFEMI/" + "K7MDENG/bPxRfiCYEXAMPLEKEY",
    "GitHub token": "gh" + "p_abcdefghijklmnopqrstuvwxyz0123456789",
    "GitHub fine-grained": "github" + "_pat_11ABCDEFG0123456789_abcdefghijklmnopqrstuv",
    "OpenAI key": "sk" + "-proj-abcdefghijklmnop1234567890",
    "Anthropic key": "sk" + "-ant-api03-abcdefghijklmnopqrstuvwxyz-12345",
    "Slack token": "xox" + "b-123456789012-1234567890123-abcdefghijklmnop",
    "Stripe key": "sk" + "_live_abcdefghijklmnop12345678",
    "Google API key": "AI" + "zaSyA1234567890abcdefghijklmnopqrstu",
    "JWT": "eyJhbGciOiJIUzI1NiJ9." + "eyJzdWIiOiIxMjM0NTY3ODkwIn0.dozjgNryP4J3jVmNHl0w5N_XgL0n3I9PlFUP0THsR8U",
    "SeamTrail token": "st_" + "mcp_49054d8b_abcdefghijklmnop",
    "Atlassian token": "ATA" + "TT3xFfGF0abcdefghijklmnopqrstuvwxyz0123",
    "GitLab token": "gl" + "pat-abcdefghij0123456789",
    "npm token": "np" + "m_abcdefghijklmnopqrstuvwxyz0123456789",
    "base64 blob": "Z2hwX2FiY2RlZmdoaWprbG1ub3BxcnN0dXZ3eHl6MDEyMzQ1Njc4OQ==",
    "hex key": "9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08",
}
WORDS = {
    "password said in words": ("my password is tiger123 for the staging box", "tiger123"),
    "password=": ("set password=hunter2 before the run", "hunter2"),
    "api_key:": ("the api_key: qwerty98765 is for stage", "qwerty98765"),
    "NAME_PASSWORD=": ("DB_PASSWORD=s3cr3t!x in the env", "s3cr3t!x"),
    "link with user and password": ("db at postgres://admin:pa55word@db.example.com:5432/app", "pa55word"),
    "token in a link": ("call https://api.example.com/v1?token=abcd1234zz&x=1 now", "abcd1234zz"),
    "Authorization header": ("send Authorization: Bearer abc.def.ghi123456 to it", "abc.def.ghi123456"),
    "card number": ("card 4111 1111 1111 1111 failed", "4111 1111 1111 1111"),
    "private key": ("key:\n-----BEGIN RSA PRIVATE KEY-----\nMIIEowIBAAKCAQEA7\n-----END RSA PRIVATE KEY-----\ndone", "MIIEowIBAAKCAQEA7"),
    "code block": ("look:\n```js\nconst internalThing = connect('prod-db');\n```\nwhy?", "internalThing"),
    "unclosed code block": ("look:\n```\nconst leftOpen = 42;\nand more", "leftOpen"),
}

for name, cmd in tools:
    for label, secret in SECRETS.items():
        for msg in (f"use {secret} for the deploy", f"key:{secret}", f"[{secret}]", f"\"{secret}\""):
            out = run(cmd, msg)
            check(f"{name}: {label} never leaves ({msg[:24]}…)", out is not None and secret not in out["hint"], json.dumps(out))
    for label, (msg, secret) in WORDS.items():
        out = run(cmd, msg)
        check(f"{name}: {label} never leaves", out is not None and secret not in out["hint"], json.dumps(out))

    # What the message is about stays: words, links, ticket numbers.
    msg = "fix the login redirect bug in SEAM-210, see https://sharbuz.atlassian.net/wiki/spaces/SE/pages/123/Refund+policy and PAY-4"
    out = run(cmd, msg)
    check(f"{name}: a plain message goes as it is", out == {"chat": "chat-1", "tickets": "PAY-4,SEAM-210", "hint": msg}, json.dumps(out))
    out = run(cmd, "update it with the new 45-day rule")
    check(f"{name}: a short message with no ticket still says what it is about", out["hint"] == "update it with the new 45-day rule" and out["tickets"] == "", json.dumps(out))
    out = run(cmd, "keep /Users/priya/work/code/seamtrail and the word internationalization")
    check(f"{name}: a long path or word without digits stays", "/Users/priya/work/code/seamtrail" in out["hint"] and "internationalization" in out["hint"], json.dumps(out))

    # A long message: its first 300 and last 200 characters, and its links.
    body = " ".join(f"word{i % 10}" for i in range(400))
    msg = "START please make a page from this. " + body + " see https://docs.example.com/spec/42 END create the page"
    out = run(cmd, msg)
    h = out["hint"]
    check(f"{name}: a long message keeps its start, its end and its links", h.startswith("START please make a page") and " … " in h and "END create the page" in h and "https://docs.example.com/spec/42" in h and len(h) <= 1500, h[:120])
    # A secret where the long message is cut never leaves in part.
    tok = "ghp_" + "Q" * 40 + "9"
    msg = ("a " * 1998) + tok + (" b" * 3000) + " the end"
    out = run(cmd, msg)
    check(f"{name}: a secret at a cut never leaves in part", "QQQQQQ" not in out["hint"] and "ghp_" not in out["hint"], out["hint"][:80])
    # A code block that starts before the cut and ends after it: its tail is code too.
    msg = "intro " + ("x " * 1500) + "\n```\n" + ("secretCodeLine();\n" * 600) + "```\n the question at the end?"
    out = run(cmd, msg)
    check(f"{name}: code across the cut never leaves", "secretCodeLine" not in out["hint"] and "the question at the end?" in out["hint"], out["hint"][-120:])
    check(f"{name}: no chat id, nothing printed", run(cmd, "hi", session="") is None)

# node and python3 give the same hint.
if len(tools) == 2:
    samples = ["fix it", "SEAM-1 and https://x.y/z?token=abc12345&a=1", "naïve café — résumé ✓ 😀 " * 40,
               "```\ncode\n``` then words AKIAIOSFODNN7EXAMPLE", "password: x y", ("é " * 3500) + "end"]
    same = all(run(tools[0][1], m) == run(tools[1][1], m) for m in samples)
    check("node and python3 give the same hint", same)

# message.sh: the cleaned body goes by POST; no secret in it; an older SeamTrail (404) is asked the old way; without
# node or python3, no words leave.
bin_ = f"{T}/bin"
os.makedirs(bin_, exist_ok=True)
with open(f"{bin_}/curl", "w") as f:
    f.write("""#!/bin/sh
printf 'ARGS:' >> "$CURL_LOG"; for a in "$@"; do printf ' %s' "$a" >> "$CURL_LOG"; done; printf '\\n' >> "$CURL_LOG"
case " $* " in *" -X POST "*) printf 'BODY:' >> "$CURL_LOG"; cat >> "$CURL_LOG"; printf '\\n' >> "$CURL_LOG";
  out=""; prev=""; for a in "$@"; do [ "$prev" = "-o" ] && out="$a"; prev="$a"; done
  printf 'news for the chat' > "$out"; printf '%s' "${POST_CODE:-200}"; exit 0 ;; esac
printf 'old way answer'
""")
os.chmod(f"{bin_}/curl", 0o755)
def hook(prompt, path, code="200"):
    log = f"{T}/curl.log"
    open(log, "w").close()
    env = dict(os.environ, PATH=path, CURL_LOG=log, POST_CODE=code, SEAMTRAIL_TOKEN="tok-1", CLAUDE_PLUGIN_DATA=f"{T}/data")
    p = subprocess.run(["sh", f"{S}/message.sh"], input=json.dumps({"session_id": "c-9", "prompt": prompt}),
                       capture_output=True, text=True, env=env, timeout=30)
    return p.stdout, open(log).read()
syspath = os.environ["PATH"]
out, log = hook("fix SEAM-210 with password=hunter2 now", f"{bin_}:{syspath}")
body = json.loads(log.split("BODY:", 1)[1].splitlines()[0]) if "BODY:" in log else {}
check("message.sh: POSTs {chat, messageId, tickets, hint} in the body, never in the address", body.get("chat") == "c-9" and len(body.get("messageId", "")) >= 8 and body.get("tickets") == "SEAM-210" and "fix SEAM-210" in body.get("hint", "") and "hint=" not in log.split("BODY:")[0], log)
check("message.sh: the secret is not in what was sent", "hunter2" not in log, log)
check("message.sh: SeamTrail's answer goes to Claude", out == "news for the chat", out)
out, log = hook("fix SEAM-210", f"{bin_}:{syspath}", code="404")
check("message.sh: an older SeamTrail (404) is asked the old way: chat id, message id and ticket numbers only", log.count("ARGS:") == 2 and "-G" in log.splitlines()[-1] and "tickets=SEAM-210" in log.splitlines()[-1] and "messageId=" in log.splitlines()[-1] and out == "old way answer", log)
# Without node or python3: a PATH with only the basics (sh, sed, grep, curl stand-in).
basic = f"{T}/basic"
os.makedirs(basic, exist_ok=True)
for tool in ("sh", "sed", "grep", "head", "sort", "paste", "cat", "dirname", "mktemp", "rm", "uname", "printf"):
    w = subprocess.run(["sh", "-c", f"command -v {tool}"], capture_output=True, text=True).stdout.strip()
    if w.startswith("/"):
        os.symlink(w, f"{basic}/{tool}")
os.symlink(f"{bin_}/curl", f"{basic}/curl")
out, log = hook("fix SEAM-210 by changing the refund window", basic)
check("message.sh: without node or python3, no words leave — only ids and ticket numbers", "refund window" not in log and "tickets=SEAM-210" in log and "BODY:" not in log, log)

print("ALL PASSED" if not fail else "SOME FAILED")
sys.exit(1 if fail else 0)
PY
