# SeamTrail · what the Devin CLI hooks share (SEAM-254). Sourced by every script here. It holds only what Devin's hook
# format needs beyond the Claude Code plugin's scripts (plugins/seamtrail/scripts), whose logic the scripts reuse.

# Where the plugin keeps its few local files (the saved marker, the chat's project, ticket numbers): Devin's own data
# folder for this plugin (PLUGIN_DATA, given to plugin hooks since Devin CLI 3000.11.92), else one of our own.
data="${PLUGIN_DATA:-${XDG_STATE_HOME:-$HOME/.local/state}/seamtrail/devin}"

# The text on stdin as the inside of a JSON string: \ " tab CR and line breaks escaped, other control characters
# dropped. sh, tr, sed and awk only — no JSON tool needed.
json_text() {
  st_tab=$(printf '\t')
  st_cr=$(printf '\r')
  LC_ALL=C tr -d '\000-\010\013\014\016-\037' \
    | LC_ALL=C sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e "s/$st_tab/\\\\t/g" -e "s/$st_cr/\\\\r/g" \
    | LC_ALL=C awk 'NR > 1 { printf "%s", "\\n" } { printf "%s", $0 }'
}

# Devin adds a hook's text to the chat only as JSON on stdout (hookSpecificOutput.additionalContext, for SessionStart
# and UserPromptSubmit). `context EVENT` hands the plain text on stdin to the agent that way; empty text adds nothing.
context() {
  st_text=$(json_text)
  [ -n "$st_text" ] || return 0
  printf '{"hookSpecificOutput":{"hookEventName":"%s","additionalContext":"%s"}}\n' "$1" "$st_text"
}

# A tool call that failed or was refused. Devin hands a tool's result to PostToolUse hooks as tool_response
# {success, output, error}; MCP's own isError may also show inside the output, its quotes escaped.
refused() {
  printf '%s' "$1" | grep -Eq '"success"[[:space:]]*:[[:space:]]*false|"error"[[:space:]]*:[[:space:]]*"[^"]|\\*"isError\\*"[[:space:]]*:[[:space:]]*true'
}
