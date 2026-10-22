#!/bin/sh
# SeamTrail · a note was saved this turn (SEAM-253: the Claude Code plugin's saved.sh, for Gemini CLI's AfterTool):
# remember, resolve, settle_question… was called, so the turn-end check (stop.sh) lets the agent finish without a
# reminder. Called with "change" (ask_seamtrail, undo_change), only when SeamTrail really changed something —
# ask_seamtrail's reply lists a step done, undo_change did not fail — because SeamTrail records that change itself, and
# a note about it would only repeat it; a question to SeamTrail saves nothing. Only SeamTrail's own tools count: Gemini
# CLI names a tool mcp_<server>_<tool>, so the hook's pattern alone would also catch another server's "resolve".
# Nothing leaves the computer.

. "$(dirname "$0")/common.sh"
[ -n "$session" ] || exit 0
seamtrail_tool || exit 0

if [ "$1" = "change" ]; then
  case "$(field tool_name)" in
    *_undo_change)
      failed && exit 0
      ;;
    *)
      # The reply arrives as text inside the hook's JSON, so its quotes are escaped: \"did\":[ … \"done\":true
      printf '%s' "$input" | grep -Eq '\\?"did\\?"[[:space:]]*:[[:space:]]*\[' || exit 0
      printf '%s' "$input" | grep -Eq '\\?"done\\?"[[:space:]]*:[[:space:]]*true' || exit 0
      ;;
  esac
fi
mkdir -p "$data" && : > "$data/saved-$session"
exit 0
