## Capture name -> ANSI `Style`, for the standalone renderer in `render.nim`.
##
## The colours themselves live in `palette.nim`; this only binds them to the
## ANSI style type. A nimtui app wants `adapters/tui.nim` instead.

import std/tables
import ./ansi, ./palette
export palette

type Theme* = object
  styles*: Table[string, Style]
  plain*: Style ## used for bytes no capture covers

proc resolve*(t: Theme, capture: string): Style =
  resolveCapture(t.styles, capture, t.plain)

proc compile*(t: Theme, captureNames: seq[string]): seq[Style] =
  ## Pre-resolve every capture id once, so rendering is an array index rather
  ## than a table lookup plus a prefix walk per span.
  compileCaptures(t.styles, captureNames, t.plain)

proc themeFromSpec*(spec: openArray[SyntaxSpec]): Theme =
  result.plain = Style()
  for s in spec:
    result.styles[s.capture] =
      if s.hex.len > 0:
        styled(hex(s.hex), bold = s.bold, italic = s.italic)
      else:
        Style(bold: s.bold, italic: s.italic)

proc defaultTheme*(): Theme =
  themeFromSpec(defaultSpec)
