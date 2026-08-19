## Terminal colour: styles, capability detection, and SGR emission.
##
## Kept separate from span assembly so a TUI with its own palette or its own
## renderer (illwill cell buffers, notcurses, a web terminal) can consume spans
## and ignore all of this.

import std/[os, strutils]

type
  ColorLevel* = enum
    clNone      ## no colour: emit nothing
    cl16        ## 8 colours + bright
    cl256       ## xterm 256-colour cube
    clTrueColor ## 24-bit

  Color* = object
    r*, g*, b*: uint8

  Style* = object
    fg*: Color
    hasFg*: bool
    bold*, dim*, italic*, underline*: bool

proc rgb*(r, g, b: uint8): Color = Color(r: r, g: g, b: b)

proc hex*(s: string): Color =
  ## `hex("#c678dd")`. Accepts an optional leading '#'.
  let h = if s.startsWith("#"): s[1 .. ^1] else: s
  doAssert h.len == 6, "expected 6 hex digits, got: " & s
  rgb(uint8(parseHexInt(h[0..1])), uint8(parseHexInt(h[2..3])),
      uint8(parseHexInt(h[4..5])))

proc fg*(c: Color): Style = Style(fg: c, hasFg: true)

proc styled*(c: Color, bold = false, dim = false, italic = false,
             underline = false): Style =
  Style(fg: c, hasFg: true, bold: bold, dim: dim, italic: italic,
        underline: underline)

proc isPlain*(s: Style): bool =
  not (s.hasFg or s.bold or s.dim or s.italic or s.underline)

proc detectColorLevel*(): ColorLevel =
  ## Environment only -- it does not check whether stdout is a tty. Callers that
  ## should degrade when piped combine this with their own isatty test, since
  ## "piped" is a policy decision (`less -R` wants colour, `wc -l` does not).
  if existsEnv("NO_COLOR"): return clNone
  let term = getEnv("TERM", "")
  if term == "" or term == "dumb": return clNone
  let ct = getEnv("COLORTERM", "").toLowerAscii()
  if ct == "truecolor" or ct == "24bit": return clTrueColor
  if "256" in term: return cl256
  cl16

proc to256*(c: Color): int =
  ## Nearest xterm-256 index: grey ramp for near-grey, 6x6x6 cube otherwise.
  let r = int(c.r)
  let g = int(c.g)
  let b = int(c.b)
  if abs(r - g) < 12 and abs(g - b) < 12 and abs(r - b) < 12:
    let level = (r + g + b) div 3
    if level < 8: return 16
    if level > 248: return 231
    return 232 + ((level - 8) * 24) div 241
  proc cube(v: int): int = (v * 5 + 127) div 255
  16 + 36 * cube(r) + 6 * cube(g) + cube(b)

proc to16*(c: Color): int =
  ## Nearest of the 16 base colours, as an SGR foreground code (30-37, 90-97).
  let r = int(c.r)
  let g = int(c.g)
  let b = int(c.b)
  let mx = max(max(r, g), b)
  let thresh = max(mx div 2, 64)
  var idx = 0
  if r >= thresh: idx = idx or 1
  if g >= thresh: idx = idx or 2
  if b >= thresh: idx = idx or 4
  # idx bits are (1=r, 2=g, 4=b), which already lines up with the ANSI order
  # black, red, green, yellow, blue, magenta, cyan, white.
  let ansi = case idx
    of 0: 0  # black
    of 1: 1  # red
    of 2: 2  # green
    of 3: 3  # yellow
    of 4: 4  # blue
    of 5: 5  # magenta
    of 6: 6  # cyan
    else: 7  # white
  let bright = mx > 180
  (if bright: 90 else: 30) + ansi

const reset* = "\e[0m"

proc sgr*(s: Style, level: ColorLevel): string =
  ## Escape sequence that turns `s` on. Pair with `reset`.
  if level == clNone or s.isPlain: return ""
  var parts: seq[string]
  if s.bold: parts.add "1"
  if s.dim: parts.add "2"
  if s.italic: parts.add "3"
  if s.underline: parts.add "4"
  if s.hasFg:
    case level
    of clTrueColor:
      parts.add "38;2;" & $s.fg.r & ";" & $s.fg.g & ";" & $s.fg.b
    of cl256:
      parts.add "38;5;" & $to256(s.fg)
    of cl16:
      parts.add $to16(s.fg)
    of clNone: discard
  if parts.len == 0: return ""
  "\e[" & parts.join(";") & "m"
