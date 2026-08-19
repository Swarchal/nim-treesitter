## Query compilation, match iteration, and predicate evaluation.
##
## The C library does not evaluate predicates -- it hands you the raw steps and
## expects you to filter matches yourself. Skipping that silently mis-highlights
## (every `(identifier) @constant (#match? @constant "^[A-Z]")` pattern would
## match every identifier), so it is done here.
##
## `#match?` needs a regex engine. By default that is `std/re`, which links
## libpcre at runtime. Build with `-d:tsNoRegex` to drop the dependency; patterns
## carrying a match predicate are then treated as unsupported and their matches
## are discarded rather than wrongly accepted.

import std/strutils
import ./capi, ./core

when not defined(tsNoRegex):
  import std/re

type
  PredicateKind = enum
    pkEq          ## #eq? / #not-eq?
    pkMatch       ## #match? / #not-match?
    pkAnyOf       ## #any-of? / #not-any-of?
    pkHasAncestor ## #has-ancestor? / #not-has-ancestor?
    pkHasParent   ## #has-parent? / #not-has-parent?

  ArgKind = enum akCapture, akString
  Arg = object
    case kind: ArgKind
    of akCapture: capture: uint32
    of akString: str: string

  Predicate = object
    kind: PredicateKind
    negated: bool
    args: seq[Arg]
    when not defined(tsNoRegex):
      rx: Regex

  Query* = object
    raw*: ptr TSQuery
    captureNames*: seq[string]
    ## Capture id -> name, e.g. 2 -> "function.call". Ids are stable for the
    ## lifetime of the query, which is what lets the renderer pre-resolve
    ## styles once instead of string-matching per span.
    predicates: seq[seq[Predicate]]
    unsupported: seq[bool]
    ## Patterns we cannot evaluate faithfully. Their matches are dropped.
    unsupportedNames*: seq[string]
    ## Predicate names that caused a drop, for diagnostics.

  Capture* = object
    node*: TSNode
    id*: int

  Match* = object
    patternIndex*: int
    captures*: seq[Capture]

proc `=destroy`(q: Query) =
  if q.raw != nil: ts_query_delete(q.raw)
proc `=copy`(dst: var Query, src: Query) {.error: "Query is not copyable".}

proc errorContext(source: string, offset: int): string =
  var line = 1
  var lineStart = 0
  for i in 0 ..< min(offset, source.len):
    if source[i] == '\n':
      inc line
      lineStart = i + 1
  let col = offset - lineStart + 1
  let lineEnd = source.find('\n', lineStart)
  let text = source[lineStart ..< (if lineEnd < 0: source.len else: lineEnd)]
  result = "at " & $line & ":" & $col & ": " & text.strip()

proc capName(q: ptr TSQuery, id: uint32): string =
  var len: uint32
  let p = ts_query_capture_name_for_id(q, id, addr len)
  result = newString(len)
  if len > 0: copyMem(addr result[0], p, len)

proc strValue(q: ptr TSQuery, id: uint32): string =
  var len: uint32
  let p = ts_query_string_value_for_id(q, id, addr len)
  result = newString(len)
  if len > 0: copyMem(addr result[0], p, len)

proc parsePredicates(q: var Query, source: string) =
  let n = int(ts_query_pattern_count(q.raw))
  q.predicates.setLen n
  q.unsupported.setLen n
  for pat in 0 ..< n:
    var steps: uint32
    let raw = ts_query_predicates_for_pattern(q.raw, uint32(pat), addr steps)
    var i = 0
    while i < int(steps):
      # Each predicate is: String(name), args..., Done
      var name = ""
      var args: seq[Arg]
      if raw[i].`type` == stepString:
        name = strValue(q.raw, raw[i].value_id)
      inc i
      while i < int(steps) and raw[i].`type` != stepDone:
        case raw[i].`type`
        of stepCapture: args.add Arg(kind: akCapture, capture: raw[i].value_id)
        of stepString: args.add Arg(kind: akString, str: strValue(q.raw, raw[i].value_id))
        of stepDone: discard
        inc i
      inc i  # skip the Done

      if name.len == 0: continue
      if name.endsWith("!"):
        # A directive (#set!, #gsub!) -- metadata for the consumer, not a filter.
        # Neovim's query files use these; ignoring them is correct here.
        continue

      let negated = name.startsWith("not-")
      let base = if negated: name[4 .. ^1] else: name
      case base
      of "eq?":
        q.predicates[pat].add Predicate(kind: pkEq, negated: negated, args: args)
      of "any-of?":
        q.predicates[pat].add Predicate(kind: pkAnyOf, negated: negated, args: args)
      of "has-ancestor?", "has-parent?":
        # Neovim extensions, not part of the C library. Implemented because the
        # runtime-loaded path reads nvim-treesitter's query files, where they are
        # common enough that dropping their patterns visibly loses colour.
        let k = if base == "has-parent?": pkHasParent else: pkHasAncestor
        q.predicates[pat].add Predicate(kind: k, negated: negated, args: args)
      of "match?":
        when defined(tsNoRegex):
          q.unsupported[pat] = true
          if name notin q.unsupportedNames: q.unsupportedNames.add name
        else:
          if args.len >= 2 and args[1].kind == akString:
            var p = Predicate(kind: pkMatch, negated: negated, args: args)
            try:
              p.rx = re(args[1].str)
              q.predicates[pat].add p
            except RegexError:
              q.unsupported[pat] = true
              if name notin q.unsupportedNames: q.unsupportedNames.add name
          else:
            q.unsupported[pat] = true
      else:
        # Unknown predicate: refuse the pattern rather than accept matches we
        # have not actually filtered.
        q.unsupported[pat] = true
        if name notin q.unsupportedNames: q.unsupportedNames.add name

proc initQuery*(lang: ptr TSLanguage, source: string): Query =
  checkAbi(lang, "initQuery")
  var
    errOffset: uint32
    errType: TSQueryError
  result.raw = ts_query_new(lang, source.cstring, uint32(source.len),
                            addr errOffset, addr errType)
  if result.raw == nil:
    raise newException(TreeSitterError, "query " & $errType & " " &
      errorContext(source, int(errOffset)))
  let nCaps = int(ts_query_capture_count(result.raw))
  result.captureNames = newSeq[string](nCaps)
  for i in 0 ..< nCaps:
    result.captureNames[i] = capName(result.raw, uint32(i))
  parsePredicates(result, source)

proc firstText(m: Match, capture: uint32, source: string): string =
  for c in m.captures:
    if uint32(c.id) == capture:
      return c.node.text(source)
  ""

proc argText(a: Arg, m: Match, source: string): string =
  case a.kind
  of akCapture: firstText(m, a.capture, source)
  of akString: a.str

proc firstNode(m: Match, capture: uint32): TSNode =
  for c in m.captures:
    if uint32(c.id) == capture: return c.node
  TSNode()

proc kindMatches(p: Predicate, n: TSNode): bool =
  if n.isNull: return false
  let k = n.kind
  for a in p.args[1 .. ^1]:
    if a.kind == akString and a.str == k: return true
  false

proc satisfies(p: Predicate, m: Match, source: string): bool =
  case p.kind
  of pkEq:
    if p.args.len < 2: return true
    result = argText(p.args[0], m, source) == argText(p.args[1], m, source)
  of pkAnyOf:
    if p.args.len < 2: return true
    let t = argText(p.args[0], m, source)
    result = false
    for a in p.args[1 .. ^1]:
      if a.kind == akString and a.str == t:
        result = true
        break
  of pkHasParent:
    if p.args.len < 2 or p.args[0].kind != akCapture: return true
    result = p.kindMatches(firstNode(m, p.args[0].capture).parent)
  of pkHasAncestor:
    if p.args.len < 2 or p.args[0].kind != akCapture: return true
    result = false
    var n = firstNode(m, p.args[0].capture)
    if not n.isNull:
      n = n.parent
      while not n.isNull:
        if p.kindMatches(n):
          result = true
          break
        n = n.parent
  of pkMatch:
    when defined(tsNoRegex):
      result = false
    else:
      if p.args.len < 1: return true
      let t = argText(p.args[0], m, source)
      result = t.len > 0 and re.contains(t, p.rx)
  if p.negated: result = not result

iterator matches*(q: Query, node: TSNode, source: string,
                  byteRange: Slice[int] = 0 .. -1): Match =
  ## Yields predicate-filtered matches. `byteRange` restricts the cursor when
  ## non-empty; for whole-file highlighting leave it at the default.
  let cursor = ts_query_cursor_new()
  defer: ts_query_cursor_delete(cursor)
  if byteRange.b >= byteRange.a:
    discard ts_query_cursor_set_byte_range(cursor, uint32(byteRange.a),
                                           uint32(byteRange.b + 1))
  ts_query_cursor_exec(cursor, q.raw, node)
  var raw: TSQueryMatch
  while ts_query_cursor_next_match(cursor, addr raw):
    let pat = int(raw.pattern_index)
    if pat < q.unsupported.len and q.unsupported[pat]: continue
    var m = Match(patternIndex: pat)
    for i in 0 ..< int(raw.capture_count):
      m.captures.add Capture(node: raw.captures[i].node,
                             id: int(raw.captures[i].index))
    var ok = true
    if pat < q.predicates.len:
      for p in q.predicates[pat]:
        if not p.satisfies(m, source):
          ok = false
          break
    if ok: yield m
