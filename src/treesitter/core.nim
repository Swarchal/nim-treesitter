## Ownership wrappers over the raw handles.
##
## Note: a `Tree` does not retain the source text -- nodes are byte offsets into
## it. The caller keeps the string alive and passes it back in where text is
## needed (predicate evaluation, span rendering).

import ./capi
export capi.TSNode, capi.TSPoint, capi.TSRange, capi.sexp

type
  TreeSitterError* = object of CatchableError

  Parser* = object
    raw*: ptr TSParser

  Tree* = object
    raw*: ptr TSTree

proc `=destroy`(p: Parser) =
  if p.raw != nil: ts_parser_delete(p.raw)
proc `=copy`(dst: var Parser, src: Parser) {.error: "Parser is not copyable".}

proc `=destroy`(t: Tree) =
  if t.raw != nil: ts_tree_delete(t.raw)
proc `=copy`(dst: var Tree, src: Tree) {.error: "Tree is not copyable".}

proc abiVersion*(lang: ptr TSLanguage): int =
  int(ts_language_abi_version(lang))

proc checkAbi*(lang: ptr TSLanguage, what: string) =
  ## Grammars built by a CLI outside the runtime's supported window must never
  ## be handed to the parser -- that is a segfault, not an error return.
  if lang == nil:
    raise newException(TreeSitterError, what & ": language function returned nil")
  let v = abiVersion(lang)
  if v < minCompatibleVersion or v > languageVersion:
    raise newException(TreeSitterError,
      what & ": grammar ABI version " & $v & " is outside this runtime's " &
      "supported range " & $minCompatibleVersion & ".." & $languageVersion &
      ". Regenerate the parser with a matching tree-sitter CLI.")

proc initParser*(lang: ptr TSLanguage): Parser =
  checkAbi(lang, "initParser")
  result.raw = ts_parser_new()
  if result.raw == nil:
    raise newException(TreeSitterError, "ts_parser_new failed")
  if not ts_parser_set_language(result.raw, lang):
    raise newException(TreeSitterError, "ts_parser_set_language rejected the grammar")

proc parse*(p: Parser, source: openArray[char]): Tree =
  ## One-shot parse of a whole buffer. tree-sitter is error tolerant, so this
  ## succeeds on malformed input too -- inspect `errorRatio` if you care.
  let s = if source.len == 0: cstring"" else: cast[cstring](unsafeAddr source[0])
  result.raw = ts_parser_parse_string(p.raw, nil, s, uint32(source.len))
  if result.raw == nil:
    raise newException(TreeSitterError, "parse failed")

proc parseIncluded*(p: Parser, source: openArray[char],
                    ranges: seq[TSRange]): Tree =
  ## Parse only `ranges` of the buffer -- how an injected language is parsed.
  ##
  ## The whole source is passed, not a substring, so the resulting nodes carry
  ## offsets into the original text and spans from every layer share one
  ## coordinate system. The ranges stay set on the parser afterwards, so this is
  ## for a parser used once rather than a long-lived one.
  if ranges.len == 0: return p.parse(source)
  if not ts_parser_set_included_ranges(p.raw,
      cast[ptr UncheckedArray[TSRange]](unsafeAddr ranges[0]),
      uint32(ranges.len)):
    raise newException(TreeSitterError, "included ranges rejected (overlapping or unordered)")
  p.parse(source)

proc range*(n: TSNode): TSRange =
  ## The node's extent, in the form `parseIncluded` wants.
  TSRange(start_byte: ts_node_start_byte(n), end_byte: ts_node_end_byte(n),
          start_point: ts_node_start_point(n), end_point: ts_node_end_point(n))

proc root*(t: Tree): TSNode = ts_tree_root_node(t.raw)

proc startByte*(n: TSNode): int = int(ts_node_start_byte(n))
proc endByte*(n: TSNode): int = int(ts_node_end_byte(n))
proc kind*(n: TSNode): string = $ts_node_type(n)
proc isNull*(n: TSNode): bool = ts_node_is_null(n)
proc hasError*(n: TSNode): bool = ts_node_has_error(n)
proc parent*(n: TSNode): TSNode = ts_node_parent(n)

proc text*(n: TSNode, source: string): string =
  ## The source slice a node covers. Cheap enough for predicate evaluation,
  ## where nodes are identifiers rather than whole files.
  let a = n.startByte
  let b = min(n.endByte, source.len)
  if a >= b: "" else: source[a ..< b]

proc errorRatio*(t: Tree): float =
  ## Fraction of nodes that are ERROR or MISSING. Snippets pulled out of context
  ## parse badly by design; a caller highlighting fragments can use this to fall
  ## back to plain text rather than emit confidently wrong colours.
  let r = t.root
  if r.isNull: return 0.0
  if not r.hasError: return 0.0
  var
    bad = 0
    total = 0
    stack = @[r]
  while stack.len > 0:
    let n = stack.pop()
    inc total
    if ts_node_is_error(n) or ts_node_is_missing(n): inc bad
    for i in 0 ..< ts_node_child_count(n):
      stack.add ts_node_child(n, i)
  if total == 0: 0.0 else: bad / total
