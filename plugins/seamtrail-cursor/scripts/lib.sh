# SeamTrail for Cursor · what the hook scripts share (SEAM-256). Sourced by them, never run on its own. POSIX sh with
# grep, sed, tr and awk only; text is read byte by byte (LC_ALL=C), so any text in a hook's input is safe to scan.

LC_ALL=C
export LC_ALL

# Where this computer keeps SeamTrail's notes about its Cursor chats: each chat's project, "saved this turn", the ticket
# numbers it talks about — never any conversation text. Cursor gives a plugin no data folder of its own.
st_state="${XDG_STATE_HOME:-$HOME/.local/state}/seamtrail/cursor"

# SeamTrail's 16 MCP tools.
st_tools="list_projects project_context search_memory remember ask_seamtrail ticket_details set_chat_project resolve
settle_question search fetch get_project get_chain widen_memory check_connection undo_change"

# A string field of the hook's input (the first one by that name), without a JSON tool.
st_field() {
  printf '%s' "$1" | grep -o "\"$2\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | head -n 1 | sed 's/.*"\([^"]*\)"$/\1/'
}

# The chat: Cursor's conversation id (sessionStart also sends it as session_id). Only an id SeamTrail accepts — 8 to 100
# letters, digits, "_" or "-" — so it is safe in a file name too. Nothing when there is none.
st_chat() {
  c=$(st_field "$1" conversation_id)
  [ -n "$c" ] || c=$(st_field "$1" session_id)
  case "$c" in *[!A-Za-z0-9_-]*) return 0 ;; esac
  if [ "${#c}" -ge 8 ] && [ "${#c}" -le 100 ]; then printf '%s' "$c"; fi
  return 0
}

# Text as one JSON string, quotes included: backslashes, quotes, tabs and line breaks escaped, other control characters
# dropped; UTF-8 passes through as it is.
st_json() {
  tab=$(printf '\t')
  cr=$(printf '\r')
  printf '%s' "$1" | tr -d '\000-\010\013\014\016-\037' \
    | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e "s/$tab/\\\\t/g" -e "s/$cr/\\\\r/g" \
    | awk 'BEGIN { printf "\"" } { printf "%s%s", (NR > 1 ? "\\n" : ""), $0 } END { printf "\"" }'
}

# Whether a name says "seamtrail", in any case.
st_says_seamtrail() {
  case "$(printf '%s' "$1" | tr 'A-Z' 'a-z')" in *seamtrail*) return 0 ;; esac
  return 1
}

# SeamTrail's own name for the MCP tool a hook input is about ("remember"), or nothing for any other tool. Cursor's docs
# show an MCP tool as "MCP:<tool>" and do not say whether the server is named too, so: when the input names the server
# (afterMCPExecution's mcp_server_name, or the "server" of a wrapped call {server, toolName, arguments}), that server
# must say "seamtrail" (this plugin's server, or a SeamTrail connection the person added); with no server named, the
# tool's own name counts, alone ("remember", "MCP:remember") or after a qualifier that says "seamtrail"
# ("mcp__seamtrail__remember").
st_tool() {
  name=$(st_field "$1" tool_name)
  server=$(st_field "$1" mcp_server_name)
  case "$name" in
    '' | MCP | mcp | CallMcpTool | MCP:CallMcpTool)
      name=$(st_field "$1" toolName)
      [ -n "$server" ] || server=$(st_field "$1" server)
      ;;
  esac
  [ -n "$name" ] || return 0
  if [ -n "$server" ] && ! st_says_seamtrail "$server"; then return 0; fi
  for t in $st_tools; do
    case "$name" in
      "$t" | MCP:"$t" | mcp:"$t")
        printf '%s' "$t"
        return 0
        ;;
      *"$t")
        if [ -n "$server" ] || st_says_seamtrail "${name%"$t"}"; then printf '%s' "$t"; fi
        return 0
        ;;
    esac
  done
  return 0
}

# Whether SeamTrail answered with an error (isError: true — its quotes may be escaped, once or twice, inside the input).
st_failed() {
  printf '%s' "$1" | grep -q '\\*"isError\\*"[[:space:]]*:[[:space:]]*true'
}
