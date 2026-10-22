# SeamTrail · what the VS Code plugin's hooks share (SEAM-255). Sourced by each script after it read its input into
# $input; never run on its own.
#
# VS Code (GitHub Copilot's agent) runs a plugin's hooks in one of two harnesses, and they speak different JSON:
# - the Copilot harness, the default for new chats since VS Code 1.143 (the GitHub Copilot runtime, shared with the
#   Copilot CLI): fields in camelCase (sessionId, toolName, toolArgs, toolResult) and answers at the top level
#   (additionalContext, modifiedArgs, decision and reason);
# - the older Local harness (and the Copilot harness under Claude-style event names): fields in snake_case
#   (session_id, tool_name, tool_input, hook_event_name …), and Local wants its answers inside hookSpecificOutput.
# A camelCase payload gets only the Copilot answer; a snake_case one gets both, since its harness cannot be told apart.
# VS Code drops a plugin hook's matcher, so each script checks the tool's name itself.

# The token and address. VS Code has no plugin setting a hook can read, so they come from the environment VS Code was
# started with (SEAMTRAIL_TOKEN, SEAMTRAIL_URL).
token="$SEAMTRAIL_TOKEN"
url="${SEAMTRAIL_URL:-https://mcp.seamtrail.com/mcp}"
# This plugin's own data folder (the Copilot runtime gives each plugin one), else one in the user's state folder.
data="${COPILOT_PLUGIN_DATA:-${PLUGIN_DATA:-${XDG_STATE_HOME:-$HOME/.local/state}/seamtrail/vscode}}"

# The first string value, in the hook's JSON, of the first of these keys that has one. No JSON tool needed.
field() {
  for _k in "$@"; do
    _v=$(printf '%s' "$input" | grep -o "\"$_k\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
    if [ -n "$_v" ]; then printf '%s' "$_v"; return 0; fi
  done
  return 1
}

# The chat's id (VS Code's session id) and the tool's name in lower case ("seamtrail-remember", "mcp_seamtrail_remember" …).
session=$(field sessionId session_id)
tool=$(field toolName tool_name | LC_ALL=C tr 'A-Z' 'a-z')

# The Copilot harness's camelCase payload.
camel() {
  printf '%s' "$input" | grep -q '"sessionId"' && ! printf '%s' "$input" | grep -q '"session_id"'
}

# One of these SeamTrail tools: the name holds SeamTrail's server name and ends with the tool's own name.
is_tool() {
  case "$tool" in *seamtrail*) ;; *) return 1 ;; esac
  for _n in "$@"; do
    case "$tool" in "$_n" | *[!a-z0-9]"$_n") return 0 ;; esac
  done
  return 1
}

# The tool call failed or was refused (Copilot sends failures to another event; Local may not).
failed() {
  printf '%s' "$input" | grep -Eq '"(isError|is_error)"[[:space:]]*:[[:space:]]*true|"(resultType|result_type)"[[:space:]]*:[[:space:]]*"(failure|error|rejected|denied)"'
}

# Text on stdin as one JSON string, quotes included, without jq, node or python. Control characters other than tab
# and newline (a CR of CRLF too) are dropped; every other byte, UTF-8 included, is kept as it is (byte-wise, C locale).
json_string() {
  _tab=$(printf '\t')
  LC_ALL=C tr -d '\000-\010\013-\037' \
    | LC_ALL=C sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e "s/$_tab/\\\\t/g" \
    | LC_ALL=C awk 'BEGIN { printf "%s", "\"" } NR > 1 { printf "%s", "\\n" } { printf "%s", $0 } END { printf "%s", "\"" }'
}
