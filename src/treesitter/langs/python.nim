## tree-sitter-python: vendored grammar, compiled in.
import std/os
import ../capi, ../registry

const grammarDir = currentSourcePath().parentDir.parentDir.parentDir.parentDir /
  "vendor" / "tree-sitter-python"

when not fileExists(grammarDir / "src" / "parser.c"):
  {.error: "grammar not vendored: run scripts/vendor.sh".}

{.compile: grammarDir / "src" / "parser.c".}
{.compile: grammarDir / "src" / "scanner.c".}

const highlightsQuery = staticRead(grammarDir / "queries" / "highlights.scm")

proc tree_sitter_python(): ptr TSLanguage {.importc, cdecl.}

register Language(
  name: "python",
  aliases: @["py"],
  exts: @[".py", ".pyi", ".pyw"],
  shebangs: @["python", "python2", "python3"],
  lang: tree_sitter_python(),
  highlights: highlightsQuery)
