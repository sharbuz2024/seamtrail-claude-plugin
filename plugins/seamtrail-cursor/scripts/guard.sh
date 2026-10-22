#!/bin/sh
# SeamTrail · guard (SEAM-230, SEAM-233) — for Cursor (SEAM-256), on preToolUse. Just before the agent calls one of
# SeamTrail's tools, it adds this chat's id (Cursor's conversation id) to the call, and the ticket numbers in the chat's
# last few messages (tickets.sh), so SeamTrail knows which chat the call came from and can bring it the news that
# touches its work. SeamTrail believes the id only for a chat this person registered (start.sh) and takes both out
# before the tool runs. It changes nothing else and never touches another server's tools.
#
# Which calls are SeamTrail's: Cursor's docs show an MCP tool as "MCP:<tool>" and do not say whether the server is
# named. So: when the input names a server, it must say "seamtrail" (this plugin's, or a SeamTrail connection the
# person added); else a tool name that says "seamtrail" ("mcp__seamtrail__remember"); else SeamTrail's own tool names
# alone — but the names other servers use too (search, fetch, list_projects, get_project, search_memory) only when the
# call carries SeamTrail's own "workingOn". A wrapped call ({server, toolName, arguments}) gets the id in its arguments.
#
# The answer is complete JSON with "permission": "allow" — Cursor blocks a call when this hook's answer is not valid
# JSON of its schema (cursor.com/docs/hooks) — and "allow" here only means "no objection": Cursor's own approval of MCP
# tools still decides (Cursor's staff, forum 2026: a hook's allow does not override it). Any other tool: no output, and
# the call goes on as it is. With no JSON tool on this computer (jq, node or python3), every call goes on as it is.

lib="$(dirname "$0")/lib.sh"
[ -f "$lib" ] || exit 0
. "$lib"

input=$(cat)
# SEAM-233: the ticket numbers tickets.sh keeps on this computer (numbers only) go with the call as chatTickets.
chat=$(st_chat "$input")
numbers=""
if [ -n "$chat" ] && [ -s "$st_state/tickets-$chat.jsonl" ]; then numbers="$st_state/tickets-$chat.jsonl"; fi

# jq: on macOS 15 and later, and on most Linux machines.
if command -v jq >/dev/null 2>&1; then
  if [ -n "$numbers" ]; then set -- --slurpfile seen "$numbers"; else set -- --argjson seen '[]'; fi
  printf '%s' "$input" | jq -c "$@" '
    def str: if type == "string" then . else "" end;
    def obj: if type == "object" then .
      elif type == "string" then ((try fromjson catch null) | if type == "object" then . else null end)
      else null end;
    def says: ascii_downcase | contains("seamtrail");
    ["list_projects", "project_context", "search_memory", "remember", "ask_seamtrail", "ticket_details",
     "set_chat_project", "resolve", "settle_question", "search", "fetch", "get_project", "get_chain",
     "widen_memory", "check_connection", "undo_change"] as $tools
    | ["search", "fetch", "list_projects", "get_project", "search_memory"] as $shared
    | ([.conversation_id, .session_id] | map(str) | map(select(. != "")) | .[0] // "") as $chat
    | select($chat | test("\\A[A-Za-z0-9_-]{8,100}\\z"))
    | (.tool_name | str) as $name
    | select(($name | ascii_downcase | startswith("mcp")) or $name == "CallMcpTool")
    | (.tool_input | obj) as $ti
    | select($ti != null)
    | ([$ti.toolName, $ti.tool_name, $ti.name] | map(str) | map(select(. != ""))) as $inner
    | (($ti | has("arguments")) and ($inner | length > 0)) as $wrapped
    | (if $wrapped then ($ti.arguments | obj) else $ti end) as $args
    | select($args != null)
    | (if $wrapped then $inner[0] else ($name | sub("^mcp:"; ""; "i")) end) as $tool
    | ([.mcp_server_name, .server_name, (.mcp_server | if type == "object" then .name else . end)]
        + (if $wrapped then [$ti.server, $ti.serverName, $ti.server_name] else [] end)
        | map(str) | map(select(. != ""))) as $servers
    | select(
        if ($servers | length) > 0 then ($servers | any(.[]; says))
        elif ($name | says) then true
        elif ($tools | any(.[]; . == $tool)) then (($shared | any(.[]; . == $tool)) | not) or ($args | has("workingOn"))
        else false end)
    | ($seen | map(.k // []) | add // [] | unique | join(",")) as $keys
    | ($args + {chatId: $chat} + (if $keys != "" then {chatTickets: $keys} else {} end)) as $next
    | {permission: "allow",
       updated_input: (if $wrapped
         then $ti + {arguments: (if ($ti.arguments | type) == "string" then ($next | tojson) else $next end)}
         else $next end)}' 2>/dev/null
  exit 0
fi

# node: wherever Cursor's users installed Node.
if command -v node >/dev/null 2>&1; then
  printf '%s' "$input" | node -e '
    let s = "";
    process.stdin.setEncoding("utf8");
    process.stdin.on("data", (d) => (s += d)).on("end", () => {
      try {
        const file = process.argv[1];
        const tools = ["list_projects", "project_context", "search_memory", "remember", "ask_seamtrail", "ticket_details",
          "set_chat_project", "resolve", "settle_question", "search", "fetch", "get_project", "get_chain",
          "widen_memory", "check_connection", "undo_change"];
        const shared = ["search", "fetch", "list_projects", "get_project", "search_memory"];
        const str = (v) => (typeof v === "string" ? v : "");
        const obj = (v) => {
          if (v && typeof v === "object" && !Array.isArray(v)) return v;
          if (typeof v === "string") {
            try { const o = JSON.parse(v); if (o && typeof o === "object" && !Array.isArray(o)) return o; } catch (e) {}
          }
          return null;
        };
        const says = (v) => v.toLowerCase().includes("seamtrail");
        const d = JSON.parse(s);
        const chat = [d.conversation_id, d.session_id].map(str).filter(Boolean)[0] || "";
        if (!/^[A-Za-z0-9_-]{8,100}$/.test(chat)) return;
        const name = str(d.tool_name);
        if (!(name.toLowerCase().startsWith("mcp") || name === "CallMcpTool")) return;
        const input = obj(d.tool_input);
        if (!input) return;
        const inner = [input.toolName, input.tool_name, input.name].map(str).filter(Boolean);
        const wrapped = Object.prototype.hasOwnProperty.call(input, "arguments") && inner.length > 0;
        const args = wrapped ? obj(input.arguments) : input;
        if (!args) return;
        const tool = wrapped ? inner[0] : name.replace(/^mcp:/i, "");
        const ms = d.mcp_server;
        const servers = [d.mcp_server_name, d.server_name, ms && typeof ms === "object" ? ms.name : ms]
          .concat(wrapped ? [input.server, input.serverName, input.server_name] : [])
          .map(str).filter(Boolean);
        const seam = servers.length ? servers.some(says)
          : says(name) ? true
          : tools.includes(tool) ? (!shared.includes(tool) || Object.prototype.hasOwnProperty.call(args, "workingOn"))
          : false;
        if (!seam) return;
        const next = Object.assign({}, args, { chatId: chat });
        if (file) {
          try {
            const keys = new Set();
            for (const l of require("fs").readFileSync(file, "utf8").split("\n").filter(Boolean))
              for (const k of JSON.parse(l).k || []) keys.add(k);
            if (keys.size) next.chatTickets = [...keys].sort().join(",");
          } catch (e) {}
        }
        const updated = wrapped
          ? Object.assign({}, input, { arguments: typeof input.arguments === "string" ? JSON.stringify(next) : next })
          : next;
        process.stdout.write(JSON.stringify({ permission: "allow", updated_input: updated }));
      } catch (e) {}
    });' "$numbers" 2>/dev/null
  exit 0
fi

# python3 — but not macOS's stand-in without the developer tools, which would open an install window.
py=$(command -v python3 2>/dev/null)
if [ -n "$py" ]; then
  if [ "$(uname)" = Darwin ] && [ "$py" = /usr/bin/python3 ] && ! xcode-select -p >/dev/null 2>&1; then exit 0; fi
  printf '%s' "$input" | "$py" -I -c '
import json, re, sys

TOOLS = ["list_projects", "project_context", "search_memory", "remember", "ask_seamtrail", "ticket_details",
         "set_chat_project", "resolve", "settle_question", "search", "fetch", "get_project", "get_chain",
         "widen_memory", "check_connection", "undo_change"]
SHARED = ["search", "fetch", "list_projects", "get_project", "search_memory"]

def s(v):
    return v if isinstance(v, str) else ""

def obj(v):
    if isinstance(v, dict):
        return v
    if isinstance(v, str):
        try:
            o = json.loads(v)
        except Exception:
            return None
        return o if isinstance(o, dict) else None
    return None

def says(v):
    return "seamtrail" in v.lower()

try:
    d = json.loads(sys.stdin.buffer.read())
except Exception:
    sys.exit(0)
if not isinstance(d, dict):
    sys.exit(0)
chat = ([x for x in (s(d.get("conversation_id")), s(d.get("session_id"))) if x] or [""])[0]
if not re.fullmatch(r"[A-Za-z0-9_-]{8,100}", chat):
    sys.exit(0)
name = s(d.get("tool_name"))
if not (name.lower().startswith("mcp") or name == "CallMcpTool"):
    sys.exit(0)
i = obj(d.get("tool_input"))
if i is None:
    sys.exit(0)
inner = [x for x in (s(i.get("toolName")), s(i.get("tool_name")), s(i.get("name"))) if x]
wrapped = "arguments" in i and len(inner) > 0
args = obj(i.get("arguments")) if wrapped else i
if args is None:
    sys.exit(0)
tool = inner[0] if wrapped else re.sub(r"^mcp:", "", name, flags=re.I)
ms = d.get("mcp_server")
servers = [s(d.get("mcp_server_name")), s(d.get("server_name")), s(ms.get("name")) if isinstance(ms, dict) else s(ms)]
if wrapped:
    servers += [s(i.get("server")), s(i.get("serverName")), s(i.get("server_name"))]
servers = [x for x in servers if x]
if servers:
    seam = any(says(x) for x in servers)
elif says(name):
    seam = True
elif tool in TOOLS:
    seam = tool not in SHARED or "workingOn" in args
else:
    seam = False
if not seam:
    sys.exit(0)
nxt = dict(args)
nxt["chatId"] = chat
if len(sys.argv) > 1 and sys.argv[1]:
    try:
        with open(sys.argv[1], encoding="utf-8") as f:
            keys = sorted({k for l in f if l.strip() for k in json.loads(l).get("k", [])})
        if keys:
            nxt["chatTickets"] = ",".join(keys)
    except Exception:
        pass
if wrapped:
    updated = dict(i)
    updated["arguments"] = json.dumps(nxt, separators=(",", ":"), ensure_ascii=False) if isinstance(i.get("arguments"), str) else nxt
else:
    updated = nxt
sys.stdout.write(json.dumps({"permission": "allow", "updated_input": updated}))
' "$numbers" 2>/dev/null
fi
exit 0
