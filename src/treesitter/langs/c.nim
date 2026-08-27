## tree-sitter-c: vendored grammar, compiled in.
##
## `.h` is claimed here because the C++ grammar is not vendored; if you add it,
## decide which of the two should win for headers.
import ../grammar

vendored "c", langExts = @[".c", ".h"]
