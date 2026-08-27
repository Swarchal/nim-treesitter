## tree-sitter-markdown: vendored grammar, compiled in.
##
## Block structure only -- headings, lists, code fences. Everything inside a
## paragraph (emphasis, links, code spans) is an injection into the separate
## `markdown_inline` grammar, so import `langs/markdown_inline` alongside this
## one unless you only care about block structure. Fenced code blocks inject the
## language named in their info string, when that grammar is registered.
import ../grammar

vendored "markdown",
  langAliases = @["md"],
  langExts = @[".md", ".markdown", ".mdown", ".mkd"]
