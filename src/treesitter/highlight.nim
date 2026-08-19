## Top level: source text in, per-line spans out.

import std/[tables, algorithm, strutils]
import ./capi, ./core, ./query, ./spans, ./registry

type
  Options* = object
    maxErrorRatio*: float
      ## Bail out to no highlighting when this fraction of nodes are ERROR or
      ## MISSING. 1.0 (the default) never bails. Callers highlighting *fragments*
      ## -- a function body, a stack-trace excerpt -- want roughly 0.3, since a
      ## fragment that fails to parse produces confidently wrong colours.
    byteRange*: Slice[int]
      ## Restrict querying to a byte range. Rarely useful for static text; parse
      ## and query the whole buffer once, then slice the lines you draw.
    maxInjectionDepth*: int
      ## How deep to follow language injections. 0 disables them entirely.
      ## Injected regions cost a parse and a query pass each, so a document that
      ## is mostly injected content costs roughly twice a plain one.

  LayerQueries = ref object
    ## Compiled queries for one injected language. `hi == nil` marks a language
    ## whose queries could not be compiled, so the failure is diagnosed once
    ## rather than on every frame.
    hi, inj: QueryRef

  Highlighter* = ref object
    language*: Language
    parser: Parser
    query: Query
    inj: QueryRef
    layers: Table[string, LayerQueries]
    layerErrors: seq[string]

  CaptureIndex = object
    ## Capture names merged across layers. Each grammar's query has its own
    ## capture id space, so ids are remapped into one table that the theme can
    ## resolve against.
    names: seq[string]
    idx: Table[string, int]

const nonStylingCaptures* = ["spell", "nospell", "conceal"]
  ## Captures that carry an editor hint rather than a colour, and are skipped so
  ## they cannot blank out the styling underneath them.
  ##
  ## Neovim *stacks* highlight groups, so its `@nospell` on the content of a
  ## markdown code span sits on top of `@markup.raw` and the colour survives.
  ## This library resolves one capture per byte -- which is what makes rendering
  ## a slice rather than a fold over layers -- so an unstyled capture arriving
  ## last would erase the colour instead. Dropping them is the closest
  ## equivalent; `@conceal` is included because we cannot hide text anyway, and
  ## leaving those characters with the surrounding markup's colour reads better
  ## than leaving them bare.

func defaultOptions*(): Options =
  Options(maxErrorRatio: 1.0, byteRange: 0 .. -1, maxInjectionDepth: 3)

proc id(ci: var CaptureIndex, name: string): int =
  ci.idx.withValue(name, v):
    return v[]
  do:
    result = ci.names.len
    ci.names.add name
    ci.idx[name] = result

proc newHighlighter*(lang: Language): Highlighter =
  ## Compiles the grammar's queries once. Reuse the highlighter across files --
  ## query compilation is the expensive part, not parsing.
  doAssert lang != nil, "newHighlighter: nil language"
  result = Highlighter(language: lang)
  result.parser = initParser(lang.lang)
  result.query = initQuery(lang.lang, lang.highlights)
  if lang.injections.len > 0:
    result.inj = newQueryRef(lang.lang, lang.injections)

proc layerFor(h: Highlighter, lang: Language): LayerQueries =
  ## Compiled queries for an injected language, compiled on first use.
  h.layers.withValue(lang.name, v):
    return v[]
  do:
    result = LayerQueries()
    try:
      result.hi = newQueryRef(lang.lang, lang.highlights)
      if lang.injections.len > 0:
        result.inj = newQueryRef(lang.lang, lang.injections)
    except TreeSitterError as e:
      # A bad query in a grammar we merely inject into must not take down the
      # host language's highlighting.
      result.hi = nil
      h.layerErrors.add lang.name & ": " & e.msg
    h.layers[lang.name] = result

proc unsupportedPredicates*(h: Highlighter): seq[string] =
  ## Predicate names in this grammar's query files that we could not evaluate;
  ## their patterns are dropped. Useful to surface once at startup rather than
  ## wondering why one construct is uncoloured.
  result = h.query.unsupportedNames
  if h.inj != nil:
    for n in h.inj.unsupportedNames:
      if n notin result: result.add n

proc layerErrors*(h: Highlighter): seq[string] =
  ## Injected languages whose queries failed to compile, and were skipped.
  h.layerErrors

type Injection = object
  langName: string
  ranges: seq[TSRange]

proc nodeRanges(n: TSNode, includeChildren: bool): seq[TSRange] =
  ## The region a `@injection.content` node contributes.
  ##
  ## Named children are masked out unless `injection.include-children` is set,
  ## matching Neovim, whose queries are written against that default. It is what
  ## keeps an interpolation inside a template literal from being parsed as part
  ## of the injected language.
  let count = ts_node_named_child_count(n)
  if includeChildren or count == 0: return @[n.range]
  var
    curByte = ts_node_start_byte(n)
    curPoint = ts_node_start_point(n)
  for i in 0 ..< count:
    let c = ts_node_named_child(n, i)
    let cs = ts_node_start_byte(c)
    if cs > curByte:
      result.add TSRange(start_byte: curByte, end_byte: cs,
                         start_point: curPoint,
                         end_point: ts_node_start_point(c))
    curByte = ts_node_end_byte(c)
    curPoint = ts_node_end_point(c)
  if ts_node_end_byte(n) > curByte:
    result.add TSRange(start_byte: curByte, end_byte: ts_node_end_byte(n),
                       start_point: curPoint, end_point: ts_node_end_point(n))

proc normalize(ranges: var seq[TSRange]) =
  ## `ts_parser_set_included_ranges` rejects unordered or overlapping ranges, and
  ## a combined injection collects them from several matches, so order is not
  ## given. Sort, then merge anything that overlaps.
  if ranges.len < 2: return
  ranges.sort(proc (a, b: TSRange): int = cmp(a.start_byte, b.start_byte))
  var merged = @[ranges[0]]
  for r in ranges[1 .. ^1]:
    if r.start_byte <= merged[^1].end_byte:
      if r.end_byte > merged[^1].end_byte:
        merged[^1].end_byte = r.end_byte
        merged[^1].end_point = r.end_point
    else:
      merged.add r
  ranges = merged

proc injections(q: Query, root: TSNode, source: string,
                selfName, parentName: string): seq[Injection] =
  ## Regions to parse with another grammar, from an `injections.scm`.
  ##
  ## The target language comes from `(#set! injection.language "x")`, or from
  ## whatever an `@injection.language` capture covers in the source -- which is
  ## how `sql"select ..."` picks its own grammar from the prefix. `injection.self`
  ## and `injection.parent` name this layer's language and its host's.
  ##
  ## Regions of a pattern marked `injection.combined` are parsed as one document
  ## rather than independently. Dockerfile is the clear case: a multi-line `RUN`
  ## is several `shell_fragment` nodes that are only valid bash once joined.
  var combined: Table[string, int]  # language -> index in result
  for m in q.matches(root, source):
    var
      content: seq[TSNode]
      langName = q.setting(m.patternIndex, "injection.language")
    if q.setting(m.patternIndex, "injection.self") != "": langName = selfName
    elif q.setting(m.patternIndex, "injection.parent") != "": langName = parentName
    let includeChildren = q.setting(m.patternIndex, "injection.include-children") != ""
    for c in m.captures:
      case q.captureNames[c.id]
      of "injection.content": content.add c.node
      of "injection.language":
        # A language read from the source: lower-cased, as grammar names are.
        if langName.len == 0: langName = c.node.text(source).toLowerAscii
      else: discard
    if langName.len == 0 or content.len == 0: continue

    var ranges: seq[TSRange]
    for n in content: ranges.add nodeRanges(n, includeChildren)
    if ranges.len == 0: continue

    if q.setting(m.patternIndex, "injection.combined") != "":
      combined.withValue(langName, i):
        result[i[]].ranges.add ranges
      do:
        combined[langName] = result.len
        result.add Injection(langName: langName, ranges: ranges)
    else:
      for r in ranges:
        result.add Injection(langName: langName, ranges: @[r])
  for inj in result.mitems:
    inj.ranges.normalize()

proc addLayer(h: Highlighter, source: string, hi: Query, inj: QueryRef,
              selfName, parentName: string, root: TSNode, layer: int,
              ci: var CaptureIndex, raw: var seq[RawSpan], opts: Options) =
  for m in hi.matches(root, source, opts.byteRange):
    for c in m.captures:
      let name = hi.captureNames[c.id]
      if name in nonStylingCaptures: continue
      raw.add RawSpan(startByte: c.node.startByte, endByte: c.node.endByte,
                      patternIndex: m.patternIndex,
                      capture: ci.id(name), layer: layer)

  if inj == nil or layer >= opts.maxInjectionDepth: return
  for injected in inj[].injections(root, source, selfName, parentName):
    let target = findLanguage(injected.langName)
    # An uninstalled injected grammar is the common case, not an error: the
    # region simply keeps the host language's highlighting.
    if target == nil or target.highlights.len == 0: continue
    let lq = h.layerFor(target)
    if lq.hi == nil: continue
    var p = initParser(target.lang)
    let t =
      try: p.parseIncluded(source, injected.ranges)
      except TreeSitterError: continue
    h.addLayer(source, lq.hi[], lq.inj, target.name, selfName, t.root,
               layer + 1, ci, raw, opts)

proc highlight*(h: Highlighter, source: string,
                opts = defaultOptions()): Highlights =
  let tree = h.parser.parse(source)
  var
    raw: seq[RawSpan]
    ci: CaptureIndex
  if opts.maxErrorRatio >= 1.0 or tree.errorRatio <= opts.maxErrorRatio:
    h.addLayer(source, h.query, h.inj, h.language.name, h.language.name,
               tree.root, 0, ci, raw, opts)
  assemble(source, ci.names, raw)

proc plainHighlights*(source: string): Highlights =
  ## Line-split with no captures. Lets a caller feed unknown filetypes through
  ## the same rendering path instead of special-casing them.
  var raw: seq[RawSpan]
  assemble(source, @[], raw)
