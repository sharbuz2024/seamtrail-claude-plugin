#!/bin/sh
# SeamTrail · guard (SEAM-253: the Claude Code plugin's guard.sh, for Gemini CLI's BeforeTool). Just before Gemini calls
# a SeamTrail tool — on this extension's SeamTrail server, or on a SeamTrail server the person added themselves, known by
# its name — it adds this chat's id (Gemini CLI's session id) to the call, so SeamTrail knows which chat the call came
# from, and the ticket numbers in the chat's last few messages (tickets.sh), so SeamTrail can bring it the news that
# touches its work. Gemini CLI merges what this hook returns into the tool's arguments, so only the two fields go back
# and no JSON tool is needed. It changes nothing else, never answers a permission question (Gemini CLI's own rules still
# decide), and never touches another server's tools. SeamTrail believes the id only for a chat this person registered
# (start.sh does that at chat start), and takes it out before the tool runs.

. "$(dirname "$0")/common.sh"
[ -n "$session" ] || exit 0
seamtrail_tool || exit 0

# The ticket numbers tickets.sh keeps on this computer (numbers only) go with the call as chatTickets.
keys=""
if [ -s "$data/tickets-$session.jsonl" ]; then
  keys=$(grep -oE '[A-Z][A-Z0-9]{1,9}-[0-9]{1,7}' "$data/tickets-$session.jsonl" | sort -u | paste -sd, -)
fi
tickets=""
[ -n "$keys" ] && tickets=",\"chatTickets\":\"$keys\""
printf '{"hookSpecificOutput":{"hookEventName":"BeforeTool","tool_input":{"chatId":"%s"%s}}}\n' "$session" "$tickets"
exit 0
