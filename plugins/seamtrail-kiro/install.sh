#!/bin/sh
# SeamTrail for Kiro · install (SEAM-264). Run it inside your repository's folder:
#
#   curl -fsSL https://raw.githubusercontent.com/sharbuz2024/seamtrail-claude-plugin/main/plugins/seamtrail-kiro/install.sh | sh
#
# It writes SeamTrail's files into the repository's .kiro folder, which the Kiro IDE (1.0 and later) and the Kiro CLI
# (V3) both read: hooks/seamtrail.json (the hooks), steering/seamtrail.md (what the agent does for them) and
# seamtrail/*.sh (the hook scripts) — SeamTrail's own files, replaced on every run, so running it again updates them —
# and adds SeamTrail to settings/mcp.json, leaving every other server, and a SeamTrail one already there, as it is.
# Commit them, and every teammate who opens the repository in Kiro gets SeamTrail. With --user
# (curl … | sh -s -- --user) it writes the same into ~/.kiro instead, for you only.
# Needs sh and curl; adding SeamTrail to an mcp.json that already lists servers needs jq, node or python3.

scope=workspace
for a in "$@"; do
  case "$a" in
    --user) scope=user ;;
    *) echo "SeamTrail: unknown option \"$a\" (the only one is --user)." >&2; exit 2 ;;
  esac
done

url="${SEAMTRAIL_URL:-https://mcp.seamtrail.com/mcp}"
case "$url" in
  https://* | http://localhost* | http://127.0.0.1*) ;;
  *) echo "SeamTrail: SEAMTRAIL_URL must start with https://" >&2; exit 2 ;;
esac
case "$url" in *[!A-Za-z0-9:/._~%?=\&+-]*) echo "SeamTrail: SEAMTRAIL_URL has a sign it cannot take." >&2; exit 2 ;; esac

# Where the files come from: this folder when run from a checkout, else GitHub (or SEAMTRAIL_KIRO_SOURCE).
src="${SEAMTRAIL_KIRO_SOURCE:-}"
if [ -z "$src" ]; then
  here=$(dirname "$0")
  if [ -f "$here/kiro/hooks/seamtrail.json" ]; then
    src="$here"
  else
    src="https://raw.githubusercontent.com/sharbuz2024/seamtrail-claude-plugin/main/plugins/seamtrail-kiro"
  fi
fi

if [ "$scope" = user ]; then
  kiro="$HOME/.kiro"
  case "$kiro" in
    *[!A-Za-z0-9_./-]*) echo "SeamTrail: your home folder's path has a space or a sign the hooks cannot carry; install it in the repository instead." >&2; exit 1 ;;
  esac
else
  if [ "$PWD" = "$HOME" ] || [ "$PWD" = / ]; then
    echo "SeamTrail: run this inside your repository's folder (cd path/to/your-repository), or add --user." >&2
    exit 1
  fi
  kiro="$PWD/.kiro"
fi

tmp=$(mktemp -d 2>/dev/null) || { echo "SeamTrail: no temporary folder." >&2; exit 1; }
trap 'rm -rf "$tmp"' EXIT
get() { # <path in the plugin folder> → $tmp/<path>
  mkdir -p "$tmp/$(dirname "$1")" || return 1
  case "$src" in
    http://* | https://*) curl -fsSL --max-time 30 "${src%/}/$1" -o "$tmp/$1" ;;
    *) cp "$src/$1" "$tmp/$1" ;;
  esac
}
scripts="start message saved picked stop remind hint"
# SEAM-233: what message.sh cleans a message with before its words leave (no code, secrets or credentials).
cleaner="hint.js hint.py hint-rules.json"
for f in $scripts; do
  get "kiro/seamtrail/$f.sh" || { echo "SeamTrail: could not get kiro/seamtrail/$f.sh from $src. Nothing was changed." >&2; exit 1; }
done
for f in $cleaner; do
  get "kiro/seamtrail/$f" || { echo "SeamTrail: could not get kiro/seamtrail/$f from $src. Nothing was changed." >&2; exit 1; }
done
for f in kiro/steering/seamtrail.md kiro/hooks/seamtrail.json; do
  get "$f" || { echo "SeamTrail: could not get $f from $src. Nothing was changed." >&2; exit 1; }
done
grep -q '"version"' "$tmp/kiro/hooks/seamtrail.json" || { echo "SeamTrail: $src did not give the hooks file. Nothing was changed." >&2; exit 1; }
if [ "$scope" = user ]; then
  # Hooks in ~/.kiro run in every workspace: the scripts by their full path.
  sed "s#sh \\.kiro/seamtrail/#sh $kiro/seamtrail/#" "$tmp/kiro/hooks/seamtrail.json" > "$tmp/hooks.json" \
    && mv "$tmp/hooks.json" "$tmp/kiro/hooks/seamtrail.json" || exit 1
fi

mkdir -p "$kiro/seamtrail" "$kiro/steering" "$kiro/hooks" "$kiro/settings" || exit 1
for f in $scripts; do
  cp "$tmp/kiro/seamtrail/$f.sh" "$kiro/seamtrail/$f.sh" && chmod +x "$kiro/seamtrail/$f.sh" || exit 1
done
for f in $cleaner; do
  cp "$tmp/kiro/seamtrail/$f" "$kiro/seamtrail/$f" || exit 1
done
cp "$tmp/kiro/steering/seamtrail.md" "$kiro/steering/seamtrail.md" || exit 1
cp "$tmp/kiro/hooks/seamtrail.json" "$kiro/hooks/seamtrail.json" || exit 1

# The MCP connection: SeamTrail, signed in through the browser the first time Kiro connects.
add_server() { # <mcp.json>: SeamTrail added inside mcpServers, everything else as it was
  out="$1.seamtrail-$$"
  if command -v jq >/dev/null 2>&1; then
    jq --arg u "$url" '.mcpServers = ((.mcpServers // {}) + {"SeamTrail": {"url": $u, "disabled": false, "autoApprove": []}})' \
      "$1" > "$out" 2>/dev/null && mv "$out" "$1" && return 0
  elif command -v node >/dev/null 2>&1; then
    node -e '
      const fs = require("fs"); const [file, u] = process.argv.slice(1);
      const d = JSON.parse(fs.readFileSync(file, "utf8"));
      if (!d || typeof d !== "object" || Array.isArray(d)) process.exit(1);
      const s = d.mcpServers || {};
      if (typeof s !== "object" || Array.isArray(s)) process.exit(1);
      d.mcpServers = Object.assign({}, s, { SeamTrail: { url: u, disabled: false, autoApprove: [] } });
      process.stdout.write(JSON.stringify(d, null, 2) + "\n");' "$1" "$url" > "$out" 2>/dev/null && mv "$out" "$1" && return 0
  else
    py=$(command -v python3 2>/dev/null)
    # Not macOS's stand-in without the developer tools, which would open an install window.
    if [ -n "$py" ] && ! { [ "$(uname)" = Darwin ] && [ "$py" = /usr/bin/python3 ] && ! xcode-select -p >/dev/null 2>&1; }; then
      "$py" -c '
import json, sys
f, u = sys.argv[1:3]
with open(f) as h:
    d = json.load(h)
s = d.get("mcpServers") if isinstance(d, dict) else None
if not isinstance(d, dict) or not isinstance(s if s is not None else {}, dict):
    sys.exit(1)
s = dict(s or {})
s["SeamTrail"] = {"url": u, "disabled": False, "autoApprove": []}
d["mcpServers"] = s
print(json.dumps(d, indent=2, ensure_ascii=False))
' "$1" "$url" > "$out" 2>/dev/null && mv "$out" "$1" && return 0
    fi
  fi
  rm -f "$out"
  return 1
}
mcp="$kiro/settings/mcp.json"
if [ ! -f "$mcp" ]; then
  printf '{\n  "mcpServers": {\n    "SeamTrail": {\n      "url": "%s",\n      "disabled": false,\n      "autoApprove": []\n    }\n  }\n}\n' "$url" > "$mcp" || exit 1
  mcp_said="settings/mcp.json: SeamTrail added."
elif grep -qi seamtrail "$mcp"; then
  mcp_said="settings/mcp.json already has SeamTrail: left as it is."
elif add_server "$mcp"; then
  mcp_said="settings/mcp.json: SeamTrail added; its other servers are as they were."
else
  mcp_said="settings/mcp.json: add SeamTrail by hand, inside \"mcpServers\": \"SeamTrail\": { \"url\": \"$url\", \"disabled\": false, \"autoApprove\": [] }"
fi

echo "SeamTrail for Kiro is in $kiro:"
echo "  hooks/seamtrail.json, steering/seamtrail.md, seamtrail/*.sh, seamtrail/hint.js, hint.py, hint-rules.json"
echo "  $mcp_said"
if [ "$scope" = workspace ] && [ -f "$HOME/.kiro/hooks/seamtrail.json" ]; then
  echo "  SeamTrail's hooks are also in ~/.kiro (from --user): Kiro would run both, so remove one of them."
fi
echo
echo "Next:"
n=1
if [ "$scope" = workspace ]; then
  echo "  $n. Commit it, so every teammate who opens the repository in Kiro gets SeamTrail:"
  echo "       git add .kiro/hooks/seamtrail.json .kiro/steering/seamtrail.md .kiro/seamtrail .kiro/settings/mcp.json"
  echo "       git commit -m \"SeamTrail for Kiro\""
  n=2
fi
echo "  $n. The hooks work as you with a SeamTrail token. Make one in SeamTrail: Settings → Agents · MCP connector → Token"
echo "     → Make a token (name it \"Kiro plugin\"). Add this line to your shell profile (~/.zshrc or ~/.bashrc),"
echo "     then quit and reopen Kiro:"
echo "       export SEAMTRAIL_TOKEN=<your token>"
if [ -n "$SEAMTRAIL_TOKEN" ]; then echo "     (SEAMTRAIL_TOKEN is already set in this terminal.)"; fi
[ "$scope" = workspace ] && echo "     Each teammate does this once, with their own token."
echo "  $((n + 1)). Open the repository in Kiro, or run kiro-cli in it. Kiro opens a browser tab: sign in to SeamTrail"
echo "     and press Allow."
exit 0
