## tree-sitter powered syntax highlighting for TUI applications.
##
## Highlights static text: parse once, get per-line non-overlapping spans, hand
## them to your renderer. No incremental editing, no rope input -- see the README
## if you need those.
##
##   import treesitter
##   import treesitter/langs/python   # registers the grammar
##
##   let src = readFile("script.py")
##   let hl = newHighlighter(findLanguage("python"))
##   let h = hl.highlight(src)          # per-line, non-overlapping spans
##
## Rendering is a separate import, so that only one styling layer is ever in
## scope: `treesitter/render` for standalone ANSI output, or
## `treesitter/adapters/tui` to hand lines to nimtui as `Spans`.
##
## Grammars are separate imports on purpose: only the ones you import get
## compiled into your binary.

import treesitter/[capi, core, query, spans, registry, detect, highlight]
export core, query, spans, registry, detect, highlight
export capi.TSLanguage, capi.TSNode, capi.TSPoint
export capi.languageVersion, capi.minCompatibleVersion, capi.tsVendorDir
