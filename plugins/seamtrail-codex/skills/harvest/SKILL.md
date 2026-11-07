---
name: harvest
description: Save memory from a document, a ticket or a pull request into SeamTrail, with a link back to it. Use when your person says "remember this doc / file / README", "remember these tickets / SEAM-12", "remember PR 42 / this pull request", or asks SeamTrail to learn what a document, ticket or pull request says.
---

# Harvest: memory from a doc, a ticket or a pull request

SeamTrail (this plugin's "seamtrail" MCP server) keeps the team's memory of a project as short notes: decisions and
why, facts, risks, blockers, questions, where the work stands. On a laptop install (SeamTrail Single User) nothing is
connected to Jira, Confluence or GitHub, so the memory of a document, a ticket or a pull request comes from this chat:
you read it as your person, write one note per thing worth keeping, each with a link back, and register the item on
the project. Never copy the whole text into SeamTrail.

## 1. Which project

The chat's project: the note SeamTrail gave this chat at its start (its projectId), or `list_projects`. Not clear →
ask your person once. No project yet → offer `create_project`.

## 2. Read the item yourself, as your person

- A file or document in the repository: read it. Its link is the repository's web address at the current commit
  (`git remote get-url origin`, `git rev-parse HEAD`): GitHub `https://github.com/<owner>/<repo>/blob/<commit>/<path>`,
  Bitbucket `https://bitbucket.org/<workspace>/<repo>/src/<commit>/<path>`. A folder with no remote: `file://<absolute
  path>`, and the commit named in the note.
- A Jira ticket: through your person's own access — an Atlassian tool in this chat, a `jira` command, or the ticket's
  text pasted by your person. `ticket_details` answers only when SeamTrail itself tracks the ticket. Its link:
  `https://<site>.atlassian.net/browse/<KEY>`.
- A pull request: `gh pr view <number> --json url,title,body,state,commits,files,reviews,comments` in the repository,
  or the pull request's address. Its link: the pull request's URL.
- Something you cannot read: say so and ask your person to paste it. Never guess what it says.

## 3. Register the item on the project, once per item

`ask_seamtrail` with the projectId: `do add_artifact {"url": "<link>", "name": "<what it is>", "tool": "link"}`.
The name says what it is: `Doc: docs/plan.md @ 1a2b3c4`, `SEAM-12: <its title>`, `PR #42: <its title>`. The item
then shows under "Where to look" in the project's context and on the project's page, and notes and drift cards can
point at it. Look at the project's context first: an item already there (same link) is not added twice.

## 4. Write the notes — one `remember` per thing

For each decision, fact, risk, blocker, question or status the item states: one plain sentence, with `projectId`,
`kind`, `subject` (the ticket key, `PR #42`, or the file name) and `url` = the item's link (a section link where
there is one, such as `…/blob/<commit>/docs/plan.md#rollout`).

- decision = a choice someone made that could have gone another way: who, what and because — only when the text
  gives the reason, never one you infer. fact = true whatever anyone chooses. status = where the work stands (a
  ticket's state, a pull request merged). blocker, risk, question as the text says.
- Say where it comes from when it matters: "the plan (docs/plan.md, 6 Nov) says …", "SEAM-12's description says …",
  "PR #42 changes …".
- Never the whole text, never code, never secrets or credentials. About ten notes per item at most unless your person
  asks for all of it — the biggest decisions first.
- `search_memory` with the subject first: a note that is already there is not written again (SeamTrail merges a
  repeat anyway and says `merged`).

Every note is saved as claimed by you for your person, and stays claimed until a person confirms it in SeamTrail.

## 5. Tell your person

Two or three lines: the item's name and link, how many notes of which kinds, and the undo SeamTrail returned
(`undo_change` with it retires a note). Say that the notes are claimed until confirmed, and the limits below where
they apply.

## Limits — say them plainly when they apply

- A file harvested this way is not watched: a later edit causes no drift by itself. Run the harvest again after a
  real change; SeamTrail then compares the new notes with the old ones.
- A ticket or pull request harvested this way is not tracked live (no webhook) until SeamTrail is connected to that
  tool.
- A `file://` link opens on the computer that has the file, not from a page in a browser.
