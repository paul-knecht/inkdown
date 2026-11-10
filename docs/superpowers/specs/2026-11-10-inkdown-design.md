# Inkdown — design

Date: 2026-11-10
Status: The user asked for this to be planned and built without a further approval
round. Lines marked **(Claude's call)** are defaults he has not discussed.

## Intent and why

The user takes handwritten notes in GoodNotes and exports them as PDF. He wants an
easy way to turn any such PDF into a Markdown file with the handwriting as
plain text. He already has a Claude Code skill that does this inside a larger
Obsidian sync, and trusts how Claude reads his handwriting. This app makes
that one step available on any PDF with one right-click or one drop.

**Reliability of the transcription is the most important quality.** Speed,
cost and looks come after it.

The user is a beginner learning Swift, Xcode and Git. Code must stay simple.

## Goals (version 1)

1. Right-click a PDF in Finder and choose "Convert to Markdown".
2. A menu bar icon: drop a PDF on it, or pick one with "Choose PDF…".
3. Claude Sonnet reads every page and writes the text as Markdown.
4. The `.md` file appears next to the PDF and is revealed in Finder.
5. Progress is visible while it runs; failures are explained in plain words.
6. Long PDFs work.

## Non-goals (later)

- Routing into the Obsidian vault, frontmatter, "Key Ideas", links
- Images, Word files, or anything that isn't a PDF
- Editing or reviewing the result inside the app
- A local model
- Launch at login, app icon

## Anti-goals

- Summarising, shortening, or "improving" the notes: every word on the page
  must be in the output
- Guessing unreadable words silently: they are marked `[ILLEGIBLE]`
- A page silently missing from the output: a page that could not be read is
  marked in the file and reported at the end
- Overwriting an existing file without asking
- The API key in Git, a source file, a plain file, a log, or the chat
- Sending anything to Anthropic other than the PDF pages being converted

## How it behaves

**Starting a conversion.** Three ways, all leading to the same code:
- Finder: right-click one or more PDFs → "Convert to Markdown" (macOS shows
  it under Services or Quick Actions in that menu).
- Menu bar: drop PDF files on the icon.
- Menu bar: click the icon → "Choose PDF…".

Opening a PDF with Inkdown ("Open With", or dropping it on the app's icon in
Finder) does the same. **(Claude's call)**

**Before any page is sent**, in this order:
1. No API key set → a message says so and offers "Set API key…".
2. The PDF can't be opened, is password-protected, or has no pages → message.
3. `<name>.md` already exists next to the PDF → ask: "Replace", "Keep Both"
   (writes `<name> 2.md`, then `3`, …) or "Cancel".
4. More than 50 pages → ask once, with the page count and a rough cost.
   **(Claude's call)**

**While converting.** The menu bar icon shows a counter such as "3/12" next
to it, and the menu's first line reads "Converting notes.pdf — page 3 of 12".
"Cancel" stops it; nothing is written. Further PDFs wait in a queue and are
converted one after another.

**When done.** The file is written and revealed in Finder. The menu's first
line shows the last result, for example "notes.md — 12 pages, about $0.31".
If some pages could not be read, a message says which.

**When it fails.** A message with a plain reason; no file is written.

**Menu:** status line, "Choose PDF…", "Cancel" (only while converting),
"Set API key…", "Quit".

## The output file **(Claude's calls, from the user's GoodNotes sync skill)**

- Same folder and name as the PDF, with `.md`.
- All content, in the original language, in reading order. Nothing summarised,
  translated or corrected.
- `##` and `###` headings where the notes have headings; `**bold**` for
  underlined or emphasised key terms; lists as Markdown lists; tables as
  Markdown tables.
- Formulas in LaTeX: `$…$` inline, `$$…$$` on their own line.
- `[ILLEGIBLE]` for a word that can't be read.
- `[?]` after a word that is mostly readable but uncertain. **(Claude's call)**
- `[DIAGRAM: short description]` for a drawing, chart or sketch.
- Each page starts with an invisible marker `<!-- Page N -->` so the text can
  be checked against the original. **(Claude's call)**
- A page that could not be read: `[PAGE N COULD NOT BE READ]`.
- Empty pages are left out.
- No frontmatter and no added sections.

## How it gets made

**Stack.** Swift, AppKit, PDFKit, Security (Keychain), `URLSession`, XCTest.
No third-party libraries. macOS 14+, built on macOS 27 with Xcode 27.2. App
Sandbox off, signed to run locally, menu-bar-only. Bundle ID `local.inkdown`.
Project set up like `~/Developer/glance` (hosted unit tests, shared scheme,
`scripts/install.sh` that installs into `/Applications`).

**One page per request (Claude's call, for reliability).** The app splits the
PDF with PDFKit and sends each page as its own one-page PDF. Reasons: the
model cannot skip or shorten a page it never sees next to others; a failed
page can be retried alone; progress and page markers are exact; request size
and output limits stop mattering, so there is no page limit beyond the cost
question at 50 pages. Up to 4 pages are in flight at once. The cost is that a
sentence running across a page break is not joined.

**The request.** Raw HTTPS to the Claude Messages API (Swift has no official
SDK). Model `claude-sonnet-5-5` (the user's choice) in one constant. The builder
must load the `claude-api` skill before writing this and follow it for the
PDF document block, headers, Sonnet 5.5's rules (thinking cannot be disabled;
effort is the control) and refusal fallback. Effort `medium`. **(Claude's
call)** Not streamed: a page's text is short.

**Failures per page.** Busy or overloaded → wait and retry (3 tries). Wrong
key, no credit, no key → stop the whole conversion with the reason. No
connection after retries → stop with the reason. A request the API rejects
as wrong → stop with the reason. Model declined, empty answer, or other error
after retries → that page becomes `[PAGE N COULD NOT BE READ]` and the rest
continues. A page whose answer was cut off keeps its text, ends with
`[PAGE N WAS CUT OFF]`, and is reported like an unreadable page (changed
after review: keeping the text loses less than discarding it). If pages
failed and no page produced any text, nothing is written. A single page
larger than 20 MB is treated as unreadable.

**Cost shown.** Each response reports the tokens used; the app adds them up
and shows an approximate dollar amount from the model's list price, held in
constants next to the model ID.

**Finder entry (Claude's call).** A macOS Service declared in the app's
`Info.plist` (`NSServices`, for PDF files). It is the built-in way for an app
to add an entry to Finder's right-click menu, needs no extra bundle or
extension, and lets the label be exactly "Convert to Markdown". The app also
declares itself able to open PDFs, which gives "Open With › Inkdown" as a
second route if the Service entry is hard to find. Alternatives rejected: a
Finder Sync extension (a second, sandboxed program; far too much for this)
and an Automator workflow (an opaque file a beginner can't read). The Service
only appears once the app is installed in `/Applications`.

**Dropping on the icon.** The status item's button window is registered for
dragged files. macOS 27 changed how the menu bar is drawn, so this must be
tried by hand; "Choose PDF…" works regardless.

**API key.** the user types it into "Set API key…"; stored in the Keychain
(service `local.inkdown`). Claude never handles it.

**Only one copy runs**, as in Glance.

## Known risks

- Handwriting accuracy is good, not perfect; formulas, cramped notes and
  diagrams are the weak spots. `[ILLEGIBLE]` and the page markers exist so
  the user can check.
- Where exactly macOS 27 lists the Service in Finder's menu, and whether
  dropping on a menu bar icon still works, are unverified until tried.
- Cost is an estimate (roughly 2 to 4 cents per page); the app shows the real
  figure after each conversion.

## Left to the builder

Prompt wording, file layout, icon symbol, exact message wording where not
given, test selection.

## Done means

- Tests pass; the app runs in the menu bar from `/Applications`.
- A test PDF made by Claude converts end to end.
- The user has converted one handwritten PDF through the right-click entry and
  one through the menu bar, and judged the result.
- Feature branch merged into `main`; nothing pushed.
- The user has been told what was not verified.
