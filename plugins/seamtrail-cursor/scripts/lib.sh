# SeamTrail for Cursor · what the hook scripts share (SEAM-256). Sourced by them, never run on its own. POSIX sh with
# grep, sed, tr and awk only; text is read byte by byte (LC_ALL=C), so any text in a hook's input is safe to scan.

LC_ALL=C
export LC_ALL

# Where this computer keeps SeamTrail's notes about its Cursor chats: the ticket numbers each one talks about — never
# any conversation text. Cursor gives a plugin no data folder of its own.
st_state="${XDG_STATE_HOME:-$HOME/.local/state}/seamtrail/cursor"

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
