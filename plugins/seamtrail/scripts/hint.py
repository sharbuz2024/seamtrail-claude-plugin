# SeamTrail · the search hint from a message (SEAM-233; founder 2026-10-24: "just make sure no secrets and credentials").
# Reads the UserPromptSubmit hook input, cuts code blocks, secrets and credentials out of the message on this computer
# (hint-rules.json, the same rules hint.js applies), and prints the body message.sh sends: {chat, tickets, hint}.
# The hint is the cleaned message when short; else its first 300 and last 200 characters, plus the links in it.
import json, re, sys

HEAD, TAIL, SHORT, FIRST, LAST, MAX = 4000, 2000, 500, 300, 200, 1500
with open(sys.argv[1]) as f:
    RULES = json.load(f)["rules"]


URL_RE = re.compile(r"https?://[^\s<>\"'\])]+")


def outside_urls(text, f):
    # A rule with skipUrls runs only on the text between links.
    out, last = [], 0
    for m in URL_RE.finditer(text):
        out.append(f(text[last:m.start()]))
        out.append(m.group(0))
        last = m.end()
    out.append(f(text[last:]))
    return "".join(out)


def clean(text):
    for r in RULES:
        flags = re.I if "i" in (r.get("flags") or "") else 0

        def put(m, r=r):
            if r.get("onlyIf") == "digit and letter" and not (re.search(r"[0-9]", m.group(0)) and re.search(r"[A-Za-z]", m.group(0))):
                return m.group(0)
            return re.sub(r"\{(\d)\}", lambda g: m.group(int(g.group(1))) or "", r["replace"])

        def apply(t, r=r, put=put, flags=flags):
            return re.sub(r["pattern"], put, t, flags=flags)

        text = outside_urls(text, apply) if r.get("skipUrls") else apply(text)
    return text


def cut(raw):
    # A long message is cut first, each cut at a space so no word is split; a tail that starts inside a code block is
    # marked so the code-block rule still takes it out. The two parts are cleaned apart, then joined.
    if len(raw) <= HEAD + TAIL:
        return raw, None
    h = HEAD
    while h > HEAD - 200 and not raw[h - 1].isspace():
        h -= 1
    t = len(raw) - TAIL
    while t < len(raw) and not raw[t].isspace():
        t += 1
    before, tail = raw[:t], raw[t:]
    for fence in ("```", "~~~"):
        if before.count(fence) % 2 == 1:
            tail = fence + tail
    return raw[:h], tail


def hint_of(raw):
    head, tail = cut(raw)
    text = re.sub(r"\s+", " ", clean(head) if tail is None else clean(head) + " … " + clean(tail)).strip()
    hint = text if len(text) <= SHORT else text[:FIRST].rstrip() + " … " + text[-LAST:].lstrip()
    links = []
    for u in re.findall(r"https?://[^\s<>\"'\])]+", text):
        if u not in links and u not in hint:
            links.append(u)
    if links:
        hint += " Links: " + " ".join(u[:200] for u in links[:5])
    return hint[:MAX]


def tickets_of(raw):
    keys = sorted({m.group(2) for m in re.finditer(r"(^|[^A-Z0-9])([A-Z][A-Z0-9]{1,9}-[0-9]{1,7})", raw)})
    return ",".join(keys[:5])


try:
    d = json.load(sys.stdin)
    prompt = d.get("prompt") if isinstance(d.get("prompt"), str) else ""
    if d.get("session_id"):
        sys.stdout.write(json.dumps({"chat": d["session_id"], "tickets": tickets_of(prompt), "hint": hint_of(prompt)}))
except Exception:
    pass
