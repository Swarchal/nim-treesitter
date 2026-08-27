## tree-sitter-html: vendored grammar, compiled in.
##
## Its injections reach for `javascript` (script elements) and `css` (style
## elements); import those grammars too if you want them coloured.
import ../grammar

vendored "html",
  langAliases = @["htm"],
  langExts = @[".html", ".htm", ".xhtml"]
