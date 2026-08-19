## A scrolling, syntax-highlighted source viewer in nimtui.
##
## The point of the example is where the work happens. Parsing and span assembly
## run *once*, in `load`; `view` only converts the visible rows to `Spans` and
## renders them. That split is what makes tree-sitter cheap enough for a redraw
## loop -- highlighting a 5000-line file on every keystroke would not be.
##
##   nim c -r --path:src --path:../nim-tui/src examples/nimtui/codeview.nim FILE

import std/[os, strutils, strformat]
import nimtui
import treesitter
import treesitter/adapters/tui
import treesitter/dynload
import treesitter/langs/[python, json]

type
  Palette = enum
    pSyntax = "syntax"   ## the library's own colours
    pUi = "ui theme"     ## derived from the app's theme

  Model = object
    path: string
    source: string
    hl: Highlights
    langName: string
    styles: seq[nimtui.Style]  ## resolved per capture id
    palette: Palette
    vp: Viewport
    size: TermSize
    theme: nimtui.Theme
    gutter: int
    status: string

const TabWidth = 4

proc restyle(m: var Model) =
  let s = case m.palette
          of pSyntax: defaultSyntaxStyles()
          of pUi: m.theme.syntaxStyles()
  m.styles = s.compile(m.hl.captureNames)

proc load(m: var Model, path: string) =
  m.path = path
  m.source = readFile(path)
  let lang = detectLanguage(path, m.source)
  if lang == nil:
    # A filetype with no grammar is not an error: line-split it and render plain.
    m.langName = "plain"
    m.hl = plainHighlights(m.source)
  else:
    m.langName = lang.name
    let h = newHighlighter(lang)
    m.hl = h.highlight(m.source)
    if h.unsupportedPredicates().len > 0:
      m.status = "unevaluated predicates: " & h.unsupportedPredicates().join(" ")
  m.gutter = len($m.hl.lineCount) + 1
  m.restyle()

proc paneHeight(m: Model): int = max(m.size.height - 2, 1)  # header + status bar

proc relayout(m: var Model) =
  m.vp.height = m.paneHeight
  m.vp.clampTop(m.hl.lineCount)

proc update(m: Model, msg: Msg): (Model, Cmd) =
  result = (m, nil)
  let total = m.hl.lineCount

  if result[0].size.handleResize(msg):
    result[0].relayout()

  elif msg of KeyMsg:
    let k = KeyMsg(msg)
    if k.matches("q", "ctrl+c"): result[1] = quitCmd()
    elif k.matches("j", "down"): result[0].vp.scrollBy(1, total)
    elif k.matches("k", "up"): result[0].vp.scrollBy(-1, total)
    elif k.matches("ctrl+d"): result[0].vp.halfPageDown(total)
    elif k.matches("ctrl+u"): result[0].vp.halfPageUp(total)
    elif k.matches("pgdown", "space"): result[0].vp.pageDown(total)
    elif k.matches("pgup"): result[0].vp.pageUp(total)
    elif k.matches("g", "home"): result[0].vp.toTop()
    elif k.matches("G", "end"): result[0].vp.toBottom(total)
    elif k.matches("t"):
      result[0].palette = if m.palette == pSyntax: pUi else: pSyntax
      result[0].restyle()

proc view(m: Model): string =
  if m.size.width == 0: return "loading…"
  let
    t = m.theme
    w = m.size.width
    total = m.hl.lineCount
    codeWidth = max(w - m.gutter - 3, 1)  # gutter + borderless scrollbar + pad

  var rows: seq[string]
  for i in m.vp.top ..< min(m.vp.top + m.vp.height, total):
    # Only the visible lines are converted -- the parse and the spans are done.
    let code = toSpans(m.source, m.hl, i, m.styles, tabWidth = TabWidth)
    let num = align($(i + 1), m.gutter - 1) & " "
    rows.add t.mutedStyle.render(num) & code.fit(codeWidth).render()
  while rows.len < m.vp.height:
    rows.add " ".repeat(m.gutter + codeWidth)

  let body = m.vp.withScrollbar(rows, total, t.borderStyle).join("\n")

  let header = statusBar(
    " " & t.titleStyle.render(m.path.lastPathPart),
    "",
    t.mutedStyle.render(&"{m.langName} · {total} lines · {$m.palette} ") , w)

  let bottom =
    if m.status.len > 0:
      statusBar(" " & t.warnStyle.render(m.status), "", "", w)
    else:
      statusBar(" " & hints({"j/k": "scroll", "^d/^u": "page", "g/G": "ends",
                            "t": "palette", "q": "quit"}), "", "", w)

  joinVertical(header, body, bottom)

when isMainModule:
  # Nim's generated parser is too large to vendor, so it is loaded from an
  # installed editor runtime if one is there. This is also how you would pick up
  # any other grammar the user already has.
  discard registerFromNvim("nim", exts = @[".nim", ".nims", ".nimble"])
  # Registered so Nim's injections can reach them: markdown in doc comments,
  # regex in re"..." literals.
  for name in ["markdown", "markdown_inline", "regex"]:
    discard registerFromNvim(name)

  var m = Model(theme: DefaultTheme, palette: pSyntax)
  let path = if paramCount() > 0: paramStr(1) else: currentSourcePath()
  if not fileExists(path):
    quit "no such file: " & path
  m.load(path)
  discard newProgram(m, update, view,
                     options = {poAltScreen, poHideCursor}).run()
