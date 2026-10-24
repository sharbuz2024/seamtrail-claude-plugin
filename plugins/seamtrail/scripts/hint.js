// SeamTrail · the search hint from a message (SEAM-233; founder 2026-10-24: "just make sure no secrets and credentials").
// Reads the UserPromptSubmit hook input, cuts code blocks, secrets and credentials out of the message on this computer
// (hint-rules.json, the same rules hint.py applies), and prints the body message.sh sends: {chat, tickets, hint}.
// The hint is the cleaned message when short; else its first 300 and last 200 characters, plus the links in it.
"use strict";
const fs = require("fs");
const HEAD = 4000, TAIL = 2000, SHORT = 500, FIRST = 300, LAST = 200, MAX = 1500;
const rules = JSON.parse(fs.readFileSync(process.argv[2], "utf8")).rules;
const chars = (s) => Array.from(s); // code points, as Python counts them

const URL_RE = /https?:\/\/[^\s<>"'\])]+/g;

// A rule with skipUrls runs only on the text between links.
function outsideUrls(text, f) {
  let out = "", last = 0;
  for (const m of text.matchAll(URL_RE)) {
    out += f(text.slice(last, m.index)) + m[0];
    last = m.index + m[0].length;
  }
  return out + f(text.slice(last));
}

function clean(text) {
  for (const r of rules) {
    const re = new RegExp(r.pattern, (r.flags || "") + "g");
    const apply = (t) =>
      t.replace(re, (...m) => {
        if (r.onlyIf === "digit and letter" && !(/[0-9]/.test(m[0]) && /[A-Za-z]/.test(m[0]))) return m[0];
        return r.replace.replace(/\{(\d)\}/g, (_, i) => m[+i] || "");
      });
    text = r.skipUrls ? outsideUrls(text, apply) : apply(text);
  }
  return text;
}

// A long message is cut first, each cut at a space so no word is split; a tail that starts inside a code block is
// marked so the code-block rule still takes it out. The two parts are cleaned apart, then joined.
function cut(raw) {
  const c = chars(raw);
  if (c.length <= HEAD + TAIL) return [raw, null];
  let h = HEAD;
  while (h > HEAD - 200 && !/\s/.test(c[h - 1])) h--;
  let t = c.length - TAIL;
  while (t < c.length && !/\s/.test(c[t])) t++;
  const before = c.slice(0, t).join("");
  let tail = c.slice(t).join("");
  for (const fence of ["```", "~~~"]) if ((before.split(fence).length - 1) % 2 === 1) tail = fence + tail;
  return [c.slice(0, h).join(""), tail];
}

function hintOf(raw) {
  const [head, tail] = cut(raw);
  const text = (tail === null ? clean(head) : clean(head) + " … " + clean(tail)).replace(/\s+/g, " ").trim();
  const c = chars(text);
  let hint = c.length <= SHORT ? text : c.slice(0, FIRST).join("").trimEnd() + " … " + c.slice(-LAST).join("").trimStart();
  const links = [...new Set(text.match(/https?:\/\/[^\s<>"'\])]+/g) || [])].filter((u) => !hint.includes(u)).slice(0, 5);
  if (links.length) hint += " Links: " + links.map((u) => chars(u).slice(0, 200).join("")).join(" ");
  return chars(hint).slice(0, MAX).join("");
}

function ticketsOf(raw) {
  const keys = new Set();
  for (const m of raw.matchAll(/(^|[^A-Z0-9])([A-Z][A-Z0-9]{1,9}-[0-9]{1,7})/g)) keys.add(m[2]);
  return [...keys].sort().slice(0, 5).join(",");
}

let s = "";
process.stdin.on("data", (d) => (s += d));
process.stdin.on("end", () => {
  try {
    const d = JSON.parse(s);
    const prompt = typeof d.prompt === "string" ? d.prompt : "";
    if (!d.session_id) return;
    process.stdout.write(JSON.stringify({ chat: d.session_id, tickets: ticketsOf(prompt), hint: hintOf(prompt) }));
  } catch (e) {}
});
