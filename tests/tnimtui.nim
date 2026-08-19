## Adapter tests. Needs nimtui on the path:
##   nimble adapter                  # uses ../nim-tui/src, or $NIMTUI_SRC
import std/[unittest, strutils]
import nimtui
import treesitter
import treesitter/adapters/tui
import treesitter/langs/[python, json]

suite "nimtui adapter":
  setup:
    setColorProfile(cpTrueColor)
    let hl = newHighlighter(findLanguage("python"))

  test "a line becomes contiguous Spans covering the whole line":
    let src = "x = f(1)\n"
    let h = hl.highlight(src)
    let styles = defaultSyntaxStyles().compile(h.captureNames)
    let line = toSpans(src, h, 0, styles)
    var joined = ""
    for it in line.items: joined.add it.text
    check joined == "x = f(1)"

  test "captured runs get a style, gaps stay plain":
    let src = "x = 42\n"
    let h = hl.highlight(src)
    let styles = defaultSyntaxStyles().compile(h.captureNames)
    let line = toSpans(src, h, 0, styles)
    var numberStyled = false
    for it in line.items:
      if it.text == "42": numberStyled = not it.style.isEmpty
    check numberStyled

  test "displayWidth is the plain-text width, not the escaped one":
    let src = "spam = 'eggs'\n"
    let h = hl.highlight(src)
    let styles = defaultSyntaxStyles().compile(h.captureNames)
    check toSpans(src, h, 0, styles).displayWidth == "spam = 'eggs'".len

  test "tabs expand before nimtui flattens them":
    let src = "if x:\n\tpass\n"
    let h = hl.highlight(src)
    let styles = defaultSyntaxStyles().compile(h.captureNames)
    let line = toSpans(src, h, 1, styles, tabWidth = 4)
    check line.displayWidth == 8   # 4 columns of indent + "pass"
    var joined = ""
    for it in line.items: joined.add it.text
    check joined == "    pass"

  test "fit truncates without cutting an escape in half":
    let src = "value = 'a long string literal here'\n"
    let h = hl.highlight(src)
    let styles = defaultSyntaxStyles().compile(h.captureNames)
    let fitted = toSpans(src, h, 0, styles).fit(12)
    check fitted.displayWidth == 12
    let rendered = fitted.render()
    check rendered.count("\e[") == 2 * rendered.count("\e[0m")

  test "styles derived from a UI theme follow its accent":
    let ui = derive(hex"#61afef")
    let styles = ui.syntaxStyles()
    check styles.resolve("keyword").fgc == ui.accent
    check styles.resolve("comment").fgc == ui.muted

  test "prefix fallback works through the adapter too":
    let styles = defaultSyntaxStyles()
    check styles.resolve("function.call.builtin") == styles.resolve("function")
    check styles.resolve("no.such.capture") == styles.plain

  test "whole-file conversion yields one Spans per line":
    let src = readFile("tests/data/sample.py")
    let h = hl.highlight(src)
    let styles = defaultSyntaxStyles().compile(h.captureNames)
    let lines = toSpans(src, h, styles, tabWidth = 4)
    check lines.len == h.lineCount
    for i, l in lines:
      check l.displayWidth >= 0
      var joined = ""
      for it in l.items: joined.add it.text
      check joined.strip(leading = true, trailing = false) ==
            h.text(src, i).replace("\t", "    ").strip(leading = true, trailing = false)

  test "another grammar works through the same path":
    let nh = newHighlighter(findLanguage("python"))
    let src = "x = 1  # comment\n"
    let h = nh.highlight(src)
    let styles = defaultSyntaxStyles().compile(h.captureNames)
    var sawComment = false
    for it in toSpans(src, h, 0, styles).items:
      if it.text.startsWith("#"): sawComment = not it.style.isEmpty
    check sawComment
