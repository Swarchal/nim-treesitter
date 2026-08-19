## The syntax palette as data, plus the capture-name fallback rule.
##
## Renderer-agnostic on purpose: `theme.nim` turns this into styles for the
## standalone ANSI renderer, and `adapters/tui.nim` turns it into
## `nimtui.Style` values. One colour list, two renderers.

import std/[tables, strutils]

type
  SyntaxSpec* = object
    ## One palette entry.
    capture*: string
    hex*: string       ## "" means "no colour, attributes only"
    bold*, italic*: bool

proc resolveCapture*[T](styles: Table[string, T], capture: string,
                        fallback: T): T =
  ## Longest matching dotted prefix wins, so an unknown capture from an
  ## unfamiliar grammar degrades instead of vanishing: `function.call.builtin`
  ## falls back to `function.call`, then `function`.
  var name = capture
  while true:
    if name in styles: return styles[name]
    let dot = name.rfind('.')
    if dot <= 0: break
    name = name[0 ..< dot]
  fallback

const defaultSpec*: seq[SyntaxSpec] = @[
  ## A dark-background default covering the capture names that the standard
  ## `queries/highlights.scm` files use. Roughly one-dark hues.
  SyntaxSpec(capture: "comment", hex: "#7f848e", italic: true),
  SyntaxSpec(capture: "string", hex: "#98c379"),
  SyntaxSpec(capture: "string.escape", hex: "#56b6c2"),
  SyntaxSpec(capture: "string.special", hex: "#56b6c2"),
  SyntaxSpec(capture: "character", hex: "#98c379"),
  SyntaxSpec(capture: "number", hex: "#e5c07b"),
  SyntaxSpec(capture: "boolean", hex: "#e5c07b"),
  SyntaxSpec(capture: "constant", hex: "#e5c07b"),
  SyntaxSpec(capture: "constant.builtin", hex: "#e5c07b"),
  SyntaxSpec(capture: "keyword", hex: "#c678dd"),
  SyntaxSpec(capture: "conditional", hex: "#c678dd"),
  SyntaxSpec(capture: "repeat", hex: "#c678dd"),
  SyntaxSpec(capture: "exception", hex: "#c678dd"),
  SyntaxSpec(capture: "include", hex: "#c678dd"),
  SyntaxSpec(capture: "operator", hex: "#56b6c2"),
  SyntaxSpec(capture: "punctuation", hex: "#7f848e"),
  SyntaxSpec(capture: "punctuation.bracket", hex: "#abb2bf"),
  SyntaxSpec(capture: "punctuation.delimiter", hex: "#7f848e"),
  SyntaxSpec(capture: "punctuation.special", hex: "#56b6c2"),
  SyntaxSpec(capture: "function", hex: "#61afef"),
  SyntaxSpec(capture: "function.builtin", hex: "#56b6c2"),
  SyntaxSpec(capture: "function.macro", hex: "#56b6c2"),
  SyntaxSpec(capture: "method", hex: "#61afef"),
  SyntaxSpec(capture: "constructor", hex: "#e5c07b"),
  SyntaxSpec(capture: "type", hex: "#e5c07b"),
  SyntaxSpec(capture: "type.builtin", hex: "#e5c07b"),
  SyntaxSpec(capture: "variable", hex: "#abb2bf"),
  SyntaxSpec(capture: "variable.builtin", hex: "#e06c75"),
  SyntaxSpec(capture: "variable.parameter", hex: "#e06c75"),
  SyntaxSpec(capture: "variable.member", hex: "#e06c75"),
  SyntaxSpec(capture: "property", hex: "#e06c75"),
  SyntaxSpec(capture: "field", hex: "#e06c75"),
  SyntaxSpec(capture: "parameter", hex: "#e06c75"),
  SyntaxSpec(capture: "label", hex: "#e06c75"),
  SyntaxSpec(capture: "attribute", hex: "#56b6c2"),
  SyntaxSpec(capture: "module", hex: "#e5c07b"),
  SyntaxSpec(capture: "namespace", hex: "#e5c07b"),
  SyntaxSpec(capture: "tag", hex: "#e06c75"),
  SyntaxSpec(capture: "tag.attribute", hex: "#e5c07b"),
  SyntaxSpec(capture: "escape", hex: "#56b6c2"),
  SyntaxSpec(capture: "error", hex: "#e06c75", bold: true),
  SyntaxSpec(capture: "none", hex: ""),

  # Markup, for text injected into comments and docstrings -- markdown inside a
  # doc comment is the common case, and without these it renders bare.
  SyntaxSpec(capture: "markup", hex: "#abb2bf"),
  SyntaxSpec(capture: "markup.heading", hex: "#61afef", bold: true),
  SyntaxSpec(capture: "markup.strong", hex: "#e5c07b", bold: true),
  SyntaxSpec(capture: "markup.italic", hex: "#e5c07b", italic: true),
  SyntaxSpec(capture: "markup.strikethrough", hex: "#7f848e"),
  SyntaxSpec(capture: "markup.underline", hex: "#61afef"),
  SyntaxSpec(capture: "markup.raw", hex: "#98c379"),
  SyntaxSpec(capture: "markup.quote", hex: "#7f848e", italic: true),
  SyntaxSpec(capture: "markup.list", hex: "#56b6c2"),
  SyntaxSpec(capture: "markup.link", hex: "#56b6c2"),
  SyntaxSpec(capture: "markup.link.url", hex: "#56b6c2", italic: true),
  SyntaxSpec(capture: "markup.link.label", hex: "#61afef"),
  SyntaxSpec(capture: "markup.math", hex: "#c678dd"),
  SyntaxSpec(capture: "diff.plus", hex: "#98c379"),
  SyntaxSpec(capture: "diff.minus", hex: "#e06c75"),
  SyntaxSpec(capture: "diff.delta", hex: "#e5c07b"),
]

