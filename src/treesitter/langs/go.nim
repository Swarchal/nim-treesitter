## tree-sitter-go: vendored grammar, compiled in.
##
## `go.mod` and `go.sum` are separate grammars upstream, and are not vendored.
import ../grammar

vendored "go", langAliases = @["golang"], langExts = @[".go"]
