## tree-sitter-regex: vendored grammar, compiled in.
##
## No extension of its own -- it exists to be injected into, by javascript's
## regex literals and by Nim's `re"..."` when that grammar comes from a runtime.
import ../grammar

vendored "regex"
