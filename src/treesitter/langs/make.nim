## tree-sitter-make: vendored grammar, compiled in.
import ../grammar

vendored "make",
  langAliases = @["makefile"],
  langExts = @[".mk", ".mak", ".make"],
  langFilenames = @["Makefile", "makefile", "GNUmakefile"]
