import std/[unittest, strutils, os, osproc]
import treesitter, treesitter/render, treesitter/dynload
import treesitter/langs/[json, python]

suite "core":
  test "grammar ABI is inside the runtime's window":
    for l in languages():
      check l.lang.abiVersion in minCompatibleVersion .. languageVersion

  test "parse and inspect":
    let src = """{"a": [1, true, null]}"""
    let p = initParser(findLanguage("json").lang)
    let t = p.parse(src)
    check t.root.kind == "document"
    check t.root.hasError == false
    check t.errorRatio == 0.0

  test "malformed input still parses, errorRatio reports it":
    let p = initParser(findLanguage("json").lang)
    let t = p.parse("""{"a": }""")
    check t.root.hasError
    check t.errorRatio > 0.0

  test "empty source":
    let p = initParser(findLanguage("json").lang)
    let t = p.parse("")
    check t.root.startByte == 0

suite "spans":
  setup:
    let hl = newHighlighter(findLanguage("json"))

  test "one line per source line, terminator excluded":
    let src = "{\n  \"k\": 1\n}\n"
    let h = hl.highlight(src)
    check h.lineCount == 3
    check h.text(src, 1) == "  \"k\": 1"

  test "trailing line without a newline still counts":
    let src = "{\n}"
    check hl.highlight(src).lineCount == 2

  test "CRLF: the \\r is not part of the line":
    let src = "{\r\n}\r\n"
    let h = hl.highlight(src)
    check h.text(src, 0) == "{"

  test "spans are sorted, non-overlapping, within the line":
    let src = readFile("tests/data/sample.py")
    let ph = newHighlighter(findLanguage("python"))
    let h = ph.highlight(src)
    for i in 0 ..< h.lineCount:
      let r = h.lineRanges[i]
      var prevEnd = -1
      for s in h.lines[i]:
        check s.startByte >= r.a
        check s.endByte <= r.b + 1
        check s.startByte >= prevEnd
        check s.startByte < s.endByte
        prevEnd = s.endByte

  test "a multi-line string is split across lines":
    let src = "x = \"\"\"one\ntwo\"\"\"\n"
    let h = newHighlighter(findLanguage("python")).highlight(src)
    proc captured(line: int): seq[string] =
      for s in h.lines[line]: result.add h.captureNames[s.capture]
    check "string" in captured(0)
    check "string" in captured(1)

  test "nested captures win over enclosing ones":
    # def f(): -- the whole definition is @function-ish, the name is narrower.
    let src = "def spam():\n    pass\n"
    let h = newHighlighter(findLanguage("python")).highlight(src)
    var nameCapture = ""
    for s in h.lines[0]:
      if src.slice(s) == "spam": nameCapture = h.captureNames[s.capture]
    check nameCapture == "function"

  test "plainHighlights line-splits without captures":
    let h = plainHighlights("a\nb\n")
    check h.lineCount == 2
    check h.lines[0].len == 0

suite "queries and predicates":
  test "python's highlights query compiles with no unsupported predicates":
    let hl = newHighlighter(findLanguage("python"))
    check hl.unsupportedPredicates().len == 0

  test "a bad query reports line and column":
    expect TreeSitterError:
      discard initQuery(findLanguage("json").lang, "(document\n(nope) @x)")

  test "#match? actually filters":
    when defined(tsNoRegex):
      skip()
    else:
      let lang = findLanguage("python").lang
      let q = initQuery(lang, """
        ((identifier) @const (#match? @const "^[A-Z][A-Z_]*$"))
      """)
      let p = initParser(lang)
      let src = "LIMIT = lower\n"
      let t = p.parse(src)
      var hits: seq[string]
      for m in q.matches(t.root, src):
        for c in m.captures: hits.add c.node.text(src)
      check hits == @["LIMIT"]

  test "unknown predicates drop their pattern rather than over-matching":
    let lang = findLanguage("python").lang
    let q = initQuery(lang, """
      ((identifier) @x (#totally-made-up? @x "y"))
    """)
    let p = initParser(lang)
    let src = "abc = 1\n"
    let t = p.parse(src)
    var n = 0
    for m in q.matches(t.root, src): inc n
    check n == 0

suite "theme":
  test "dotted prefix fallback":
    let t = defaultTheme()
    check t.resolve("function.call.builtin") == t.resolve("function")
    check t.resolve("string.escape") != t.resolve("string")
    check t.resolve("nothing.like.this").isPlain

  test "compile resolves per capture id":
    let t = defaultTheme()
    let styles = t.compile(@["comment", "zzz.unknown"])
    check styles[0] == t.resolve("comment")
    check styles[1].isPlain

suite "ansi":
  test "no colour emits nothing":
    check defaultTheme().resolve("comment").sgr(clNone) == ""

  test "truecolor, 256 and 16 all encode a foreground":
    let s = fg hex"#61afef"
    check s.sgr(clTrueColor) == "\e[38;2;97;175;239m"
    check s.sgr(cl256).startsWith("\e[38;5;")
    check s.sgr(cl16) in ["\e[94m", "\e[34m", "\e[96m", "\e[36m"]

  test "greys land on the 256 grey ramp":
    check to256(hex"#808080") in 232 .. 255

  test "attributes come before the colour":
    check styled(hex"#ffffff", bold = true).sgr(clTrueColor) ==
      "\e[1;38;2;255;255;255m"

suite "render":
  test "plain text round-trips when colour is off":
    let src = readFile("tests/data/sample.py")
    let h = newHighlighter(findLanguage("python")).highlight(src)
    # toAnsi joins lines and does not append a terminator.
    check src.toAnsi(h, level = clNone) == src.strip(leading = false, chars = {'\n'})

  test "every escape is closed":
    let src = readFile("tests/data/sample.py")
    let h = newHighlighter(findLanguage("python")).highlight(src)
    let rendered = src.toAnsi(h, level = clTrueColor)
    check rendered.count("\e[") == 2 * rendered.count(reset)

  test "stripping escapes gives back the source":
    let src = readFile("tests/data/sample.py")
    let h = newHighlighter(findLanguage("python")).highlight(src)
    var plain = ""
    var i = 0
    let rendered = src.toAnsi(h, level = clTrueColor)
    while i < rendered.len:
      if rendered[i] == '\e':
        while i < rendered.len and rendered[i] != 'm': inc i
        inc i
      else:
        plain.add rendered[i]
        inc i
    check plain == src.strip(leading = false, chars = {'\n'})

  test "tabs expand to the next stop across span boundaries":
    let src = "\tx = 1\n"
    let h = newHighlighter(findLanguage("python")).highlight(src)
    let styles = defaultTheme().compile(h.captureNames)
    var line = ""
    renderLine(line, src, h, 0, styles, clNone, tabWidth = 4)
    check line == "    x = 1"

  test "utf-8 survives rendering":
    let src = "s = \"héllo — ok\"\n"
    let h = newHighlighter(findLanguage("python")).highlight(src)
    check src.toAnsi(h, level = clNone).contains("héllo — ok")

suite "detection":
  test "by extension":
    check detectLanguage("a/b/c.py").name == "python"
    check detectLanguage("A/B/C.PY").name == "python"
    check detectLanguage("data.json").name == "json"

  test "by shebang, including env":
    check detectLanguage("script", "#!/usr/bin/env python3\n").name == "python"
    check detectLanguage("script", "#!/usr/bin/python\n").name == "python"

  test "unknown is nil, not an error":
    check detectLanguage("a.zzz") == nil
    check detectLanguage("", "") == nil
    # No grammar is vendored for Nim -- it comes from dynload, see below.
    check detectLanguage("x.nim") == nil

suite "dynload":
  # Builds a shared object from the vendored json grammar, so the runtime-loading
  # path is tested without depending on what is installed on the machine.
  setup:
    let jsonDir = tsVendorDir.parentDir / "tree-sitter-json"
    let soPath = getTempDir() / "ts-test-json" & ".so"
    let cc = findExe("cc")
    let built =
      if cc.len == 0: false
      else:
        let (_, code) = execCmdEx(quoteShell(cc) & " -shared -fPIC -O0 -o " &
          quoteShell(soPath) & " " & quoteShell(jsonDir / "src" / "parser.c"))
        code == 0 and fileExists(soPath)

  test "load a parser from a shared object and highlight with it":
    if not built: skip()
    else:
      let lang = loadLanguage(soPath, "json", readFile(jsonDir / "queries" / "highlights.scm"),
                              exts = @[".json"])
      check lang.lang.abiVersion in minCompatibleVersion .. languageVersion
      let h = newHighlighter(lang).highlight("""{"k": 1}""")
      check h.lineCount == 1
      check h.lines[0].len > 0

  test "a missing symbol raises rather than returning a broken language":
    if not built: skip()
    else:
      expect TreeSitterError:
        discard loadLanguage(soPath, "json", "", symbol = "tree_sitter_nope")

  test "a missing file raises":
    expect TreeSitterError:
      discard loadLanguage(getTempDir() / "no-such-parser.so", "x", "")

  test "finders return empty for a language nobody has":
    check findParser("definitely-not-a-language") == ""
    check findHighlights("definitely-not-a-language") == ""

  test "an installed grammar loads, when one is installed":
    # Machine-dependent by nature: asserts only that if a parser and its query
    # are both present, loading them works end to end.
    if findParser("nim").len == 0 or findHighlights("nim").len == 0: skip()
    else:
      let lang = loadFromNvim("nim", exts = @[".nim"])
      check lang != nil
      let hl = newHighlighter(lang)
      let src = "let x = 1  # comment\n"
      let h = hl.highlight(src)
      var sawComment = false
      for sp in h.lines[0]:
        if src.slice(sp).startsWith("#"):
          sawComment = h.captureNames[sp.capture].startsWith("comment")
      check sawComment

suite "injections":
  # A grammar that ships no injections query gets one here, so the machinery is
  # tested against the vendored grammars rather than whatever is installed.
  setup:
    let py = findLanguage("python")
    proc withInjections(label, injQuery: string): Language =
      result = Language(name: "py-" & label, lang: py.lang,
                        highlights: py.highlights, injections: injQuery)
      register result
    proc captures(h: Highlights, src: string): seq[string] =
      for i in 0 ..< h.lineCount:
        for sp in h.lines[i]: result.add src.slice(sp) & ":" & h.captureNames[sp.capture]
    const src = "x = '{\"k\": 12}'\n"

  test "an injected grammar captures inside the host's region":
    let lang = withInjections("content",
      """((string_content) @injection.content (#set! injection.language "json"))""")
    let h = newHighlighter(lang).highlight(src)
    # 12 is a number to json; python sees only one long string.
    check "12:number" in h.captures(src)

  test "maxInjectionDepth 0 disables them":
    let lang = withInjections("off",
      """((string_content) @injection.content (#set! injection.language "json"))""")
    var opts = defaultOptions()
    opts.maxInjectionDepth = 0
    let h = newHighlighter(lang).highlight(src, opts)
    check "12:number" notin h.captures(src)
    check "\'{\"k\": 12}\':string" in h.captures(src)

  test "named children are masked out by default":
    # (string) has string_start/content/end children, so masking leaves only the
    # quotes -- nothing for json to match. This is Neovim's default, which its
    # query files are written against.
    let lang = withInjections("excl",
      """((string) @injection.content (#set! injection.language "json"))""")
    check "12:number" notin newHighlighter(lang).highlight(src).captures(src)

  test "injection.include-children takes the whole node":
    let lang = withInjections("incl",
      """((string) @injection.content (#set! injection.language "json")
          (#set! injection.include-children))""")
    check "12:number" in newHighlighter(lang).highlight(src).captures(src)

  test "an unavailable injected language leaves the host's colouring":
    let lang = withInjections("missing",
      """((string_content) @injection.content (#set! injection.language "no-such-lang"))""")
    let h = newHighlighter(lang).highlight(src)
    check "12:number" notin h.captures(src)
    check "\'{\"k\": 12}\':string" in h.captures(src)

  test "injection.self re-injects the host language":
    let lang = withInjections("self",
      """((string_content) @injection.content (#set! injection.self))""")
    # Parsed as python, so the content is a dict-ish expression, not one string.
    check newHighlighter(lang).highlight(src).captures(src).len > 3

  test "a language from the source picks its own grammar":
    let lang = withInjections("bycapture", """
      (assignment
        left: (identifier) @injection.language
        right: (string (string_content) @injection.content))
    """)
    let s2 = "json = '{\"k\": 12}'\n"
    check "12:number" in newHighlighter(lang).highlight(s2).captures(s2)

  test "injected spans win over the host's for the same bytes":
    let lang = withInjections("layer",
      """((string_content) @injection.content (#set! injection.language "json"))""")
    let h = newHighlighter(lang).highlight(src)
    for sp in h.lines[0]:
      if src.slice(sp) == "12":
        check h.captureNames[sp.capture] == "number"

  test "non-styling captures never reach the spans":
    let lang = withInjections("nonstyling",
      """((string_content) @injection.content (#set! injection.language "json"))""")
    let h = newHighlighter(lang).highlight(src)
    for name in h.captureNames:
      check name notin nonStylingCaptures

  test "combined injections parse their regions as one document":
    # Dockerfile is the real case: a multi-line RUN is several shell_fragment
    # nodes that only form valid bash once joined.
    if findParser("dockerfile").len == 0 or findHighlights("dockerfile").len == 0 or
       findParser("bash").len == 0 or findHighlights("bash").len == 0: skip()
    else:
      discard registerFromNvim("bash")
      let docker = loadFromNvim("dockerfile")
      let s2 = "RUN if true; then \\\n  echo hi; \\\n  fi\n"
      let h = newHighlighter(docker).highlight(s2)
      # `fi` closes the `if` only if both fragments landed in one bash tree.
      var sawFi = false
      for i in 0 ..< h.lineCount:
        for sp in h.lines[i]:
          if s2.slice(sp) == "fi" and h.captureNames[sp.capture].startsWith("keyword"):
            sawFi = true
      check sawFi

  test "markdown injected into a doc comment, when the grammars are installed":
    if findParser("nim").len == 0 or findParser("markdown_inline").len == 0: skip()
    else:
      discard registerFromNvim("markdown_inline")
      let nim = loadFromNvim("nim", exts = @[".nim"])
      let hl = newHighlighter(nim)
      check hl.layerErrors().len == 0
      let s2 = "proc f() =\n  ## Doc with *emphasis*.\n  discard\n"
      let h = hl.highlight(s2)
      var sawItalic = false
      for sp in h.lines[1]:
        if h.captureNames[sp.capture] == "markup.italic": sawItalic = true
      check sawItalic
