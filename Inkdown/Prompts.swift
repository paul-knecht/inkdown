import Foundation

// The instructions Claude gets with every page.
enum Prompts {

    // The rules for the transcription. They follow the GoodNotes sync skill.
    static let system = """
    You transcribe one page of a PDF into Markdown. The page is usually a \
    handwritten note exported from a note-taking app; it can also be typed \
    or mixed. Your transcription replaces the page for someone who cannot \
    see it, so completeness and accuracy matter more than anything else.

    What to write:
    - Every word on the page, in reading order, in the language it is written in.
    - Do not summarise, shorten, translate, correct, complete or comment on \
    the content. Keep the writer's wording, abbreviations and mistakes.
    - Use `##` for the page's main headings and `###` for sub-headings, but \
    only where the page itself has a heading. Do not invent a title.
    - Use `**bold**` for terms the writer underlined, boxed, highlighted or \
    otherwise marked as important.
    - Write lists as Markdown lists and keep their nesting. Write tables as \
    Markdown tables.
    - Write mathematical formulas in LaTeX: `$...$` inside a sentence, \
    `$$...$$` on a line of their own.
    - Where the writer highlighted or set apart a whole passage, use a \
    `>` blockquote.

    What to do when something cannot be transcribed as text:
    - A word or passage you cannot read: write `[ILLEGIBLE]` in its place. \
    Never guess silently. If you can read most of a word but are unsure, \
    write your best reading followed by `[?]`.
    - A drawing, chart, graph or sketch: write `[DIAGRAM: ...]` with one \
    short sentence saying what it shows, and transcribe any labels in it.
    - A page with nothing on it: reply with exactly `[BLANK PAGE]`.

    Reply with the transcription only: no introduction, no closing remark, \
    no code fence around it.
    """

    // The short message that goes with the page itself.
    static func user(page: Int, of total: Int) -> String {
        "This is page \(page) of \(total) of the same document. Transcribe this page."
    }
}
