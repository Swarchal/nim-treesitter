## nimtui adapter: `Highlights` -> `nimtui.Spans`, one per line.
##
## Import this instead of `treesitter/ansi` when the consumer is a nimtui app.
## nimtui already owns styling, colour-profile downgrade and column-accurate
## truncation, so nothing here re-implements them -- a highlighted line becomes
## an ordinary `Spans`, which means `fit`, `elide`, `withScrollbar` and every
## layout helper work on code exactly as they do on any other line.
##
## nimtui is not a dependency of the core library; only this module needs it.
##
##   import nimtui
##   import treesitter, treesitter/adapters/tui
##   import treesitter/langs/nim as nimLang
##
##   let hl = newHighlighter(findLanguage("nim"))
##   let h = hl.highlight(src)
##   let styles = defaultSyntaxStyles().compile(h.captureNames)
##   let line = toSpans(src, h, 0, styles, tabWidth = 2)
##   echo line.fit(width).render()

import std/tables
import nimtui
import ../spans as tsspans
import ../palette
export tsspans.Highlights

type
  SyntaxStyles* = object
    ## Capture name -> nimtui.Style, with the same dotted-prefix fallback the
    ## standalone theme uses.
    styles*: tables.Table[string, nimtui.Style]
    plain*: nimtui.Style

proc resolve*(s: SyntaxStyles, capture: string): nimtui.Style =
  resolveCapture(s.styles, capture, s.plain)

proc compile*(s: SyntaxStyles, captureNames: seq[string]): seq[nimtui.Style] =
  ## Pre-resolve per capture id. Do this once per file, not once per frame.
  result = newSeq[nimtui.Style](captureNames.len)
  for i, n in captureNames:
    result[i] = s.resolve(n)

proc stylesFromSpec*(spec: openArray[SyntaxSpec]): SyntaxStyles =
  for sp in spec:
    var st = nimtui.Style()
    if sp.hex.len > 0: st = st.fg(nimtui.hex(sp.hex))
    var attrs: seq[Attr]
    if sp.bold: attrs.add aBold
    if sp.italic: attrs.add aItalic
    if attrs.len > 0: st = st.with(attrs)
    result.styles[sp.capture] = st

proc defaultSyntaxStyles*(): SyntaxStyles =
  ## The library's own palette, independent of the app's UI theme.
  stylesFromSpec(defaultSpec)

proc syntaxStyles*(t: nimtui.Theme): SyntaxStyles =
  ## Derive a syntax palette from a nimtui UI theme, so highlighted code sits in
  ## the same colour world as the rest of the app instead of importing a second
  ## palette that happens to clash. Coarser than `defaultSyntaxStyles` by
  ## necessity -- a UI theme has a handful of semantic slots, not thirty syntax
  ## ones -- but it tracks whatever accent the app was built with.
  result.plain = nimtui.Style().fg(t.fg)
  result.styles = {
    "comment":     nimtui.Style().fg(t.muted).with(aItalic),
    "string":      nimtui.Style().fg(t.success),
    "character":   nimtui.Style().fg(t.success),
    "number":      nimtui.Style().fg(t.warn),
    "boolean":     nimtui.Style().fg(t.warn),
    "constant":    nimtui.Style().fg(t.warn),
    "keyword":     nimtui.Style().fg(t.accent).with(aBold),
    "conditional": nimtui.Style().fg(t.accent).with(aBold),
    "repeat":      nimtui.Style().fg(t.accent).with(aBold),
    "exception":   nimtui.Style().fg(t.accent).with(aBold),
    "include":     nimtui.Style().fg(t.accent).with(aBold),
    "operator":    nimtui.Style().fg(t.secondary),
    "punctuation": nimtui.Style().fg(t.muted),
    "function":    nimtui.Style().fg(t.info),
    "method":      nimtui.Style().fg(t.info),
    "type":        nimtui.Style().fg(t.secondary),
    "constructor": nimtui.Style().fg(t.secondary),
    "variable":    nimtui.Style().fg(t.fg),
    "property":    nimtui.Style().fg(t.secondary),
    "field":       nimtui.Style().fg(t.secondary),
    "parameter":   nimtui.Style().fg(t.secondary),
    "attribute":   nimtui.Style().fg(t.secondary),
    "module":      nimtui.Style().fg(t.secondary),
    "namespace":   nimtui.Style().fg(t.secondary),
    "error":       nimtui.Style().fg(t.error).with(aBold),
    # Markup, for languages injected into comments and docstrings.
    "markup":                nimtui.Style().fg(t.fg),
    "markup.heading":        nimtui.Style().fg(t.accent).with(aBold),
    "markup.strong":         nimtui.Style().fg(t.fg).with(aBold),
    "markup.italic":         nimtui.Style().fg(t.fg).with(aItalic),
    "markup.strikethrough":  nimtui.Style().fg(t.muted).with(aStrike),
    "markup.raw":            nimtui.Style().fg(t.success),
    "markup.quote":          nimtui.Style().fg(t.muted).with(aItalic),
    "markup.list":           nimtui.Style().fg(t.secondary),
    "markup.link":           nimtui.Style().fg(t.info).with(aUnderline),
    "diff.plus":             nimtui.Style().fg(t.success),
    "diff.minus":            nimtui.Style().fg(t.error),
  }.toTable

proc expandTabs(text: string, startCol: int, tabWidth: int): (string, int) =
  ## Tabs are expanded here rather than left to nimtui: `Spans.add` flattens
  ## control characters to a single space, which would silently collapse indented
  ## code. Column tracking carries across runs so alignment survives colouring.
  if tabWidth <= 0: return (text, startCol)
  var
    outp = newStringOfCap(text.len)
    col = startCol
  for ch in text:
    if ch == '\t':
      let n = tabWidth - (col mod tabWidth)
      for _ in 0 ..< n: outp.add ' '
      col += n
    else:
      outp.add ch
      if (uint8(ch) and 0xC0'u8) != 0x80'u8: inc col
  (outp, col)

proc toSpans*(source: string, h: Highlights, line: int,
              styles: seq[nimtui.Style], tabWidth = 0,
              plain = nimtui.Style()): nimtui.Spans =
  ## One source line as a nimtui `Spans`. Uncaptured stretches become runs with
  ## `plain`, so the result is contiguous and safe to `fit`/`elide`.
  let r = h.lineRanges[line]
  if r.b < r.a: return
  var col = 0
  var pos = r.a

  proc emit(s: var nimtui.Spans, a, b: int, st: nimtui.Style) =
    if a >= b: return
    let (text, newCol) = expandTabs(source[a ..< b], col, tabWidth)
    col = newCol
    s.add(text, st)

  for sp in h.lines[line]:
    result.emit(pos, sp.startByte, plain)
    let st = if sp.capture < styles.len: styles[sp.capture] else: plain
    result.emit(sp.startByte, sp.endByte, st)
    pos = sp.endByte
  result.emit(pos, r.b + 1, plain)

proc toSpans*(source: string, h: Highlights, styles: seq[nimtui.Style],
              tabWidth = 0, plain = nimtui.Style()): seq[nimtui.Spans] =
  ## Every line. Convenient for a viewport that slices with `window`; for very
  ## large files convert only the visible rows instead.
  result = newSeq[nimtui.Spans](h.lineCount)
  for i in 0 ..< h.lineCount:
    result[i] = toSpans(source, h, i, styles, tabWidth, plain)
