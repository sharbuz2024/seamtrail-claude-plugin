# SeamTrail for Gemini CLI · what the hook scripts share (SEAM-253). Each script sources this file first; it is never
# run on its own, and it reads the hook's JSON input from stdin.
#
# The token: the extension's "SeamTrail token" setting, which Gemini CLI keeps in the system keychain and hands to this
# extension's own hooks as SEAMTRAIL_TOKEN; else SEAMTRAIL_TOKEN from the environment Gemini CLI was started in. The
# address: SEAMTRAIL_URL — only a company that runs its own SeamTrail sets it — else SeamTrail's own.
token="${SEAMTRAIL_TOKEN:-}"
url="${SEAMTRAIL_URL:-https://mcp.seamtrail.com/mcp}"
# Gemini CLI gives an extension's hooks no data folder of their own, so what they keep (the saved and asked markers,
# the chat's project, ticket numbers) lives in this computer's state folder — never inside the extension, which an
# update replaces. Only this person can read it.
data="${XDG_STATE_HOME:-$HOME/.local/state}/seamtrail/gemini"
umask 077
input=$(cat)

# The first text value of a field in the hook's input. Gemini CLI writes its own fields (session_id, tool_name …)
# before a tool's arguments and result, and quotes inside a result arrive escaped, so the first match is Gemini CLI's.
field() {
  printf '%s' "$input" | grep -o "\"$1\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | head -1 | sed 's/.*"\([^"]*\)"$/\1/'
}

# The chat id: Gemini CLI's session id (a UUID; a resumed chat keeps its id, /clear starts a new one). Anything that
# does not look like an id is dropped: SeamTrail would ignore it, and it names files here.
session=$(field session_id)
[ -n "$session" ] || session="${GEMINI_SESSION_ID:-}"
case "$session" in *[!A-Za-z0-9_-]*) session="" ;; esac

# A SeamTrail tool: Gemini CLI names an MCP tool mcp_<server>_<tool>, and this extension's server is "seamtrail" (any
# server whose name holds "seamtrail" counts, like a SeamTrail connection the person added themselves).
seamtrail_tool() {
  case "$(field tool_name | tr '[:upper:]' '[:lower:]')" in
    mcp_*seamtrail*) return 0 ;;
    *) return 1 ;;
  esac
}

# The tool failed: Gemini CLI hands the hook an "error" object beside the result (an MCP isError result becomes one).
failed() {
  printf '%s' "$input" | grep -Eq '"error"[[:space:]]*:[[:space:]]*\{|"isError"[[:space:]]*:[[:space:]]*true'
}

# Text (stdin) → the inside of a JSON string, with sed alone: backslashes, quotes and tabs escaped, line ends as \n,
# other control characters dropped.
json_text() {
  LC_ALL=C tr -d '\000-\010\013-\037' \
    | LC_ALL=C sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e "s/$(printf '\t')/\\\\t/g" \
    | LC_ALL=C sed -n -e 'H' -e '${x;s/\n/\\n/g;s/^\\n//;p;}'
}

# Hands text (stdin) to Gemini as context for this chat; $1 is the hook's event. Gemini CLI takes only JSON from a hook:
# plain text would be shown to the person, not given to the agent. Nothing to say: nothing printed.
context() {
  text=$(json_text)
  [ -n "$text" ] || return 0
  printf '{"hookSpecificOutput":{"hookEventName":"%s","additionalContext":"%s"}}\n' "$1" "$text"
}

# The turn-end reminder (stop.sh) begins with these words. Gemini CLI sends it to the agent as the next prompt, so the
# message hooks see it too and must tell it from the person's own message.
reminder="SeamTrail: nothing was saved this turn."
