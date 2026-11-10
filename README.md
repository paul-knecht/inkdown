# Inkdown

A small macOS menu bar app that turns a PDF of handwritten notes into a
Markdown file with the handwriting as plain text. Claude reads the pages.

## What it does

You give Inkdown a PDF, for example notes exported from GoodNotes. It sends
each page to Claude, and writes a `.md` file with the same name next to the
PDF. When it is done, the new file is shown in Finder.

## Install

You need Xcode. In Terminal, from this folder:

```bash
./scripts/install.sh
```

This builds the app, puts it in `/Applications` and starts it. A small page
icon appears in the menu bar.

Then click the icon, choose **Set API key…** and paste your Anthropic API key
(create one at console.anthropic.com). The key is stored in the macOS
Keychain, never in a file.

## Three ways to convert a PDF

1. **Right-click in Finder:** right-click a PDF and choose
   **Convert to Markdown**. macOS lists it under *Quick Actions* or
   *Services* in that menu.
2. **Drop on the icon:** drag a PDF onto the Inkdown icon in the menu bar.
3. **Choose a file:** click the icon and choose **Choose PDF…**.

*Open With › Inkdown* works too.

While Inkdown works, the icon shows a counter such as `3/12`, and the first
line of its menu says which page it is on. **Cancel** in the menu stops the
conversion; nothing is written.

## What the Markdown file looks like

- Everything on the page, in the original language. Nothing is summarised,
  translated or corrected.
- `##` and `###` headings, `**bold**` for underlined or highlighted terms,
  lists and tables as Markdown.
- Formulas in LaTeX (`$…$` and `$$…$$`).
- `[ILLEGIBLE]` where a word could not be read, and `[?]` after a word
  Claude was unsure about.
- `[DIAGRAM: …]` with a short description where there is a drawing.
- `<!-- Page 3 -->` before each page. These markers are invisible in a
  Markdown preview and let you compare the text with the original page.
- `[PAGE 3 COULD NOT BE READ]` if a page failed. Inkdown also tells you.
- `[PAGE 3 WAS CUT OFF]` if a page had more text than fits in one answer.
  Inkdown tells you about that too.

If a file with that name already exists, Inkdown asks whether to replace it
or keep both.

## Cost

Each page costs roughly 2 to 4 cents with Claude Sonnet. After a conversion,
the first line of the menu shows what it actually cost, for example
`notes.md — 12 pages, about $0.31`. Above 50 pages Inkdown asks before it
starts. API usage is billed by Anthropic and is separate from a Claude
subscription.

## Privacy

The pages of the PDF you convert are sent to Anthropic's API, and nothing
else. Inkdown keeps no copy and no history.

## Limits

- Handwriting recognition is good, not perfect. Formulas, cramped notes and
  diagrams are the weak spots, so check important passages.
- Each page is read on its own. A sentence that runs across a page break is
  not joined.
- Password-protected PDFs are not converted.
- Only PDFs. Export GoodNotes notes as PDF first.

## For developers

```bash
xcodebuild -project Inkdown.xcodeproj -scheme Inkdown -derivedDataPath build test
```

The model and its price are constants at the top of
`Inkdown/ClaudeClient.swift`. The instructions Claude gets are in
`Inkdown/Prompts.swift`.

## Licence

MIT, see [LICENSE](LICENSE).
