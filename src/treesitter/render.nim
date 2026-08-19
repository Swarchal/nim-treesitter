## Standalone ANSI rendering: `Highlights` -> escaped text.
##
## This is the `cat`-shaped path, and what to use when the consumer is not a
## nimtui app. It is a separate import from the core library so that a nimtui
## consumer never pulls in a second `Style`/`hex`/colour-detection layer that
## collides with the one nimtui already provides -- use
## `treesitter/adapters/tui <adapters/tui.html>`_ there.

import ./spans, ./theme, ./ansi
export theme, ansi

proc put(dest: var string, col: var int, source: string,
         a, b, tabWidth: int) =
  if tabWidth <= 0:
    dest.add source[a ..< b]
    return
  for i in a ..< b:
    if source[i] == '\t':
      let n = tabWidth - (col mod tabWidth)
      for _ in 0 ..< n: dest.add ' '
      col += n
    else:
      dest.add source[i]
      # Continuation bytes of a UTF-8 sequence do not advance a column.
      if (uint8(source[i]) and 0xC0'u8) != 0x80'u8: inc col

proc renderLine*(dest: var string, source: string, h: Highlights, line: int,
                 styles: seq[Style], level: ColorLevel, tabWidth = 0) =
  ## Appends one styled line (no trailing newline) to `dest`.
  ##
  ## `styles` comes from `theme.compile(h.captureNames)`. `tabWidth > 0` expands
  ## tabs to the next multiple of that width, tracked across span boundaries so
  ## alignment survives colouring.
  let r = h.lineRanges[line]
  if r.b < r.a: return
  var col = 0
  var pos = r.a
  for s in h.lines[line]:
    if s.startByte > pos: put(dest, col, source, pos, s.startByte, tabWidth)
    let st = if s.capture < styles.len: styles[s.capture] else: Style()
    let esc = st.sgr(level)
    if esc.len > 0:
      dest.add esc
      put(dest, col, source, s.startByte, s.endByte, tabWidth)
      dest.add reset
    else:
      put(dest, col, source, s.startByte, s.endByte, tabWidth)
    pos = s.endByte
  if pos <= r.b: put(dest, col, source, pos, r.b + 1, tabWidth)

proc toAnsi*(source: string, h: Highlights, t = defaultTheme(),
             level = detectColorLevel(), tabWidth = 0): string =
  ## Whole buffer, newline separated. Convenience for `cat`-shaped output; a TUI
  ## drawing rows should call `renderLine` per visible row instead.
  let styles = t.compile(h.captureNames)
  result = newStringOfCap(source.len + source.len div 4)
  for i in 0 ..< h.lineCount:
    renderLine(result, source, h, i, styles, level, tabWidth)
    if i < h.lineCount - 1: result.add '\n'
