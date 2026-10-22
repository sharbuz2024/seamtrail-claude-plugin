#!/bin/sh
# SeamTrail · a note was saved this turn (SEAM-215) — for Cursor (SEAM-256), on postToolUse and afterMCPExecution
# (either one is enough; both together change nothing). After SeamTrail's remember, resolve, settle_question or
# widen_memory, the turn-end check (stop.sh) lets the agent finish without a reminder. After ask_seamtrail or
# undo_change, only when SeamTrail really changed something — ask_seamtrail's reply lists a step done, undo_change did
# not fail — because SeamTrail records that change itself, and a note about it would only repeat it; a question to
# SeamTrail saves nothing. Another server's tools never count (lib.sh, st_tool). Nothing leaves the computer.

lib="$(dirname "$0")/lib.sh"
[ -f "$lib" ] || exit 0
. "$lib"

input=$(cat)
chat=$(st_chat "$input")
[ -n "$chat" ] || exit 0

case "$(st_tool "$input")" in
  remember | resolve | settle_question | widen_memory) ;;
  undo_change)
    st_failed "$input" && exit 0
    ;;
  ask_seamtrail)
    # The reply arrives as text inside the hook's JSON (Cursor stringifies it once more), so its quotes may be escaped
    # once or twice: \"did\":[ … \"done\":true
    printf '%s' "$input" | grep -q '\\*"did\\*"[[:space:]]*:[[:space:]]*\[' || exit 0
    printf '%s' "$input" | grep -q '\\*"done\\*"[[:space:]]*:[[:space:]]*true' || exit 0
    ;;
  *) exit 0 ;;
esac
mkdir -p "$st_state" 2>/dev/null && : > "$st_state/saved-$chat"
exit 0
