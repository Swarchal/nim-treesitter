## Span assembly: turn query matches into per-line, non-overlapping runs.
##
## Overlap resolution uses a paint buffer -- one capture id per source byte,
## painted lowest-priority first so nested captures win over the outer ones that
## contain them. That is the behaviour editors expect: a `function_definition`
## captured as @function is overwritten by the inner identifier's
## @function.name, and a @string covering a whole literal is overwritten by an
## @escape inside it.
##
## Priority, lowest first:
##   1. longer spans (the enclosing node)
##   2. earlier patterns in the query file
##
## So for an identical range the *last* matching pattern wins. That is what the
## upstream Rust highlighter does -- "once a highlighting pattern is found for
## the current node, keep iterating over any later highlighting patterns that
## also match this node and set the match to it" -- and query files depend on
## it: tree-sitter-python's highlights.scm opens with a catch-all
## `(identifier) @variable` that every later, more specific pattern overrides.
##
## Cost is 2 bytes per source byte, transient. For the file sizes a TUI renders
## that is a fine trade for not having to reason about interval trees.

import std/algorithm

const noCapture* = -1

type
  RawSpan* = object
    startByte*, endByte*: int
    patternIndex*: int
    capture*: int

  Span* = object
    startByte*, endByte*: int  ## absolute byte offsets into the source
    capture*: int              ## index into Highlights.captureNames

  Highlights* = object
    captureNames*: seq[string]
    lines*: seq[seq[Span]]
      ## One entry per source line. Spans are sorted, non-overlapping, clipped
      ## to the line, and exclude the line terminator. Gaps mean "no capture" --
      ## render those bytes unstyled.
    lineRanges*: seq[Slice[int]]
      ## Byte range of each line's content, terminator excluded. `b < a` for an
      ## empty line.

proc cmpPriority(x, y: RawSpan): int =
  let lx = x.endByte - x.startByte
  let ly = y.endByte - y.startByte
  if lx != ly: return cmp(ly, lx)              # longer (outer) painted first
  result = cmp(x.patternIndex, y.patternIndex) # earlier pattern painted first

proc emitLine(h: var Highlights, buf: seq[int32], contentStart, contentEnd: int) =
  ## Run-length encode one line out of the paint buffer.
  var spans: seq[Span]
  var j = contentStart
  while j < contentEnd:
    let v = buf[j]
    var k = j + 1
    while k < contentEnd and buf[k] == v: inc k
    if v != 0:
      spans.add Span(startByte: j, endByte: k, capture: int(v) - 1)
    j = k
  h.lines.add spans
  h.lineRanges.add contentStart .. contentEnd - 1

proc assemble*(source: string, captureNames: seq[string],
               raw: var seq[RawSpan]): Highlights =
  ## Paint `raw` into per-line spans. `raw` is sorted in place.
  result.captureNames = captureNames

  var buf = newSeq[int32](source.len)  # 0 = none, else capture id + 1
  raw.sort(cmpPriority)
  for s in raw:
    let a = max(s.startByte, 0)
    let b = min(s.endByte, source.len)
    if a >= b: continue
    let v = int32(s.capture + 1)
    for i in a ..< b:
      buf[i] = v

  # Walk lines, run-length encoding the paint buffer within each.
  var lineStart = 0
  var i = 0
  while i < source.len:
    if source[i] == '\n':
      var contentEnd = i
      if contentEnd > lineStart and source[contentEnd - 1] == '\r': dec contentEnd
      result.emitLine(buf, lineStart, contentEnd)
      lineStart = i + 1
    inc i
  # Trailing line without a terminator. A source ending in "\n" has no extra
  # line, which is what a renderer drawing rows expects.
  if lineStart < source.len or source.len == 0:
    result.emitLine(buf, lineStart, source.len)

proc lineCount*(h: Highlights): int = h.lines.len

proc text*(h: Highlights, source: string, line: int): string =
  ## The content of a line, terminator excluded.
  let r = h.lineRanges[line]
  if r.b < r.a: "" else: source[r]

proc slice*(source: string, s: Span): string = source[s.startByte ..< s.endByte]
