## tree-sitter-javascript: vendored grammar, compiled in.
##
## The grammar covers JSX too, but the extra `highlights-jsx.scm` upstream ships
## is a separate file; only `highlights.scm` is used here.
import ../grammar

vendored "javascript",
  langAliases = @["js", "jsx", "node"],
  langExts = @[".js", ".jsx", ".mjs", ".cjs"],
  langShebangs = @["node", "nodejs"]
