## Top level: source text in, per-line spans out; plus an ANSI renderer.

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

  Highlighter* = ref object
    language*: Language
    parser: Parser
    query: Query

func defaultOptions*(): Options =
  Options(maxErrorRatio: 1.0, byteRange: 0 .. -1)

proc newHighlighter*(lang: Language): Highlighter =
  ## Compiles the grammar's highlights query once. Reuse the highlighter across
  ## files -- query compilation is the expensive part, not parsing.
  doAssert lang != nil, "newHighlighter: nil language"
  result = Highlighter(language: lang)
  result.parser = initParser(lang.lang)
  result.query = initQuery(lang.lang, lang.highlights)

proc unsupportedPredicates*(h: Highlighter): seq[string] =
  ## Predicate names in this grammar's query file that we could not evaluate;
  ## their patterns are dropped. Useful to surface once at startup rather than
  ## wondering why one construct is uncoloured.
  h.query.unsupportedNames

proc highlight*(h: Highlighter, source: string,
                opts = defaultOptions()): Highlights =
  let tree = h.parser.parse(source)
  var raw: seq[RawSpan]
  if opts.maxErrorRatio >= 1.0 or tree.errorRatio <= opts.maxErrorRatio:
    for m in h.query.matches(tree.root, source, opts.byteRange):
      for c in m.captures:
        raw.add RawSpan(startByte: c.node.startByte, endByte: c.node.endByte,
                        patternIndex: m.patternIndex, capture: c.id)
  assemble(source, h.query.captureNames, raw)

proc plainHighlights*(source: string): Highlights =
  ## Line-split with no captures. Lets a caller feed unknown filetypes through
  ## the same rendering path instead of special-casing them.
  var raw: seq[RawSpan]
  assemble(source, @[], raw)
