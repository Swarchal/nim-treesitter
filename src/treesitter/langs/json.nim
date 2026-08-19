## tree-sitter-json: vendored grammar, compiled in.
import std/os
import ../capi, ../registry

const grammarDir = currentSourcePath().parentDir.parentDir.parentDir.parentDir /
  "vendor" / "tree-sitter-json"

when not fileExists(grammarDir / "src" / "parser.c"):
  {.error: "grammar not vendored: run scripts/vendor.sh".}

{.compile: grammarDir / "src" / "parser.c".}

const highlightsQuery = staticRead(grammarDir / "queries" / "highlights.scm")

proc tree_sitter_json(): ptr TSLanguage {.importc, cdecl.}

register Language(
  name: "json",
  aliases: @[],
  exts: @[".json", ".jsonl"],
  shebangs: @[],
  lang: tree_sitter_json(),
  highlights: highlightsQuery)
