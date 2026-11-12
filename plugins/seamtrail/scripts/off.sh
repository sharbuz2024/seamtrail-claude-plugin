#!/bin/sh
# SeamTrail · a chat with SeamTrail off (SEAM-325; founder 2026-11-13: "can we also give an option of no seamtrail? ..
# if selected no .. it will not use in that chat?"). The person picked "No SeamTrail" for this chat: picked.sh, or
# SeamTrail at chat start, left off-<chat> in the plugin's data folder, and from then on every hook stays quiet in the
# chat — nothing from it leaves this computer. What Claude hears instead, at the chat's start and with each message, is
# this line, made here: the chat id is in it so that turning SeamTrail back on (set_chat_project) needs nothing added by
# the guard. `off.sh <chat>`; prints nothing for an id that is not plain.

case "$1" in "" | *[!A-Za-z0-9_-]*) exit 0 ;; esac
printf '%s\n' "SeamTrail is off in this chat: your person chose \"No SeamTrail\", so nothing from it goes to SeamTrail. Do not use SeamTrail's tools or follow SeamTrail's instructions here unless your person asks. If they want SeamTrail back in this chat, ask which project, then call set_chat_project with chatId \"$1\" and their answer (projectId, or none: true). Never show the chat id to your person."
