## Standalone ANSI rendering: `Highlights` -> escaped text.
##
## This is the `cat`-shaped path, and what to use when the consumer is not a
## nimtui app. It is a separate import from the core library so that a nimtui
## consumer never pulls in a second `Style`/`hex`/colour-detection layer that
## collides with the one nimtui already provides -- use
## `treesitter/adapters/tui <adapters/tui.html>`_ there.

import ./spans, ./theme, ./ansi
export theme, ansi

proc renderLine*(
    dest: var string,
    source: string,
    h: Highlights,
    line: int,
    styles: seq[Style],
    level: ColorLevel,
    tabWidth = 0,
    plain = Style(),
) =
  ## Appends one styled line (no trailing newline) to `dest`.
  ##
  ## `styles` comes from `theme.compile(h.captureNames)`; bytes no capture
  ## covers get `plain` (the theme's `plain`, as `toAnsi` passes it).
  ## `tabWidth > 0` expands tabs to the next multiple of that width, tracked
  ## across span boundaries so alignment survives colouring.
  var col = 0
  let plainEsc = plain.sgr(level)
  for (a, b, capture) in h.runs(line):
    let esc =
      if capture in 0 ..< styles.len:
        styles[capture].sgr(level)
      else:
        plainEsc
    dest.add esc
    dest.addExpanded(col, source, a, b, tabWidth)
    if esc.len > 0:
      dest.add reset

proc toAnsi*(
    source: string,
    h: Highlights,
    t = defaultTheme(),
    level = detectColorLevel(),
    tabWidth = 0,
): string =
  ## Whole buffer, newline separated. Convenience for `cat`-shaped output; a TUI
  ## drawing rows should call `renderLine` per visible row instead.
  let styles = t.compile(h.captureNames)
  result = newStringOfCap(source.len + source.len div 4)
  for i in 0 ..< h.lineCount:
    renderLine(result, source, h, i, styles, level, tabWidth, t.plain)
    if i < h.lineCount - 1:
      result.add '\n'
