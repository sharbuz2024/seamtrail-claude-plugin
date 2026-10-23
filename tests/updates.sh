#!/bin/sh
# SEAM-273 · updates.json, the list SeamTrail reads to tell a chat on an older plugin how to update it: well formed, one
# entry per plugin in this repository, and each version equal to its plugin's own — a release that forgets to bump one
# or the other fails here. Needs python3.
here=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
python3 -I - "$here" <<'PY'
import json, os, re, sys
root = sys.argv[1]
fail = 0
def check(label, cond, info=""):
    global fail
    print(("ok   " if cond else "FAIL ") + label + ("" if cond else f" — {info}"))
    fail |= not cond
d = json.load(open(os.path.join(root, "updates.json")))
plugins = d.get("plugins", {})
# Where each assistant's plugin says its version; Kiro's kit has no manifest, its start script says it.
MANIFEST = {
    "claude-code": "plugins/seamtrail/.claude-plugin/plugin.json",
    "cursor": "plugins/seamtrail-cursor/.cursor-plugin/plugin.json",
    "vscode": "plugins/seamtrail-vscode/plugin.json",
    "codex": "plugins/seamtrail-codex/.codex-plugin/plugin.json",
    "gemini": "plugins/seamtrail-gemini/gemini-extension.json",
    "devin": "plugins/seamtrail-devin/.devin-plugin/plugin.json",
    "kiro": "plugins/seamtrail-kiro/kiro/seamtrail/start.sh",
}
def version_of(path):
    full = os.path.join(root, path)
    if path.endswith(".json"):
        return json.load(open(full)).get("version")
    m = re.search(r'^version="([^"]+)"$', open(full).read(), re.M)
    return m.group(1) if m else None
here_now = [k for k, p in MANIFEST.items() if os.path.exists(os.path.join(root, p))]
check("every plugin in this repository has an entry", sorted(here_now) == sorted(plugins), f"plugins {sorted(here_now)}, entries {sorted(plugins)}")
for key, e in plugins.items():
    check(f"{key}: name, version, update commands, after", isinstance(e.get("name"), str) and re.fullmatch(r"\d+\.\d+\.\d+", str(e.get("version"))) is not None and isinstance(e.get("update"), list) and len(e["update"]) > 0 and all(isinstance(c, str) and c.strip() for c in e["update"]) and isinstance(e.get("after"), str), json.dumps(e))
    check(f"{key}: where, autoUpdate and tried have the right types", (e.get("where") is None or isinstance(e.get("where"), str)) and (e.get("autoUpdate") is None or isinstance(e.get("autoUpdate"), str)) and isinstance(e.get("tried"), bool), json.dumps(e))
    if key in MANIFEST:
        v = version_of(MANIFEST[key])
        check(f"{key}: version {e.get('version')} equals the plugin's own ({v})", v == e.get("version"))
    else:
        check(f"{key}: a plugin SeamTrail knows", False, "add it to MANIFEST")
print("ALL PASSED" if not fail else "SOME FAILED")
sys.exit(1 if fail else 0)
PY
