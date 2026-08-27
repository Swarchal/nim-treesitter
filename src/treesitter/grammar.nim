## The vendoring boilerplate every `langs/` module used to repeat.
##
## A grammar module is metadata plus a call:
##
##   import ../grammar
##   vendored "python", langAliases = @["py"], langExts = @[".py", ".pyi"],
##     langShebangs = @["python", "python3"]
##
## Everything else is derived from the name: the vendored directory is
## `vendor/tree-sitter-<name>`, the C entry point is `tree_sitter_<name>`, and
## `scanner.c` and `injections.scm` are compiled in or read when the grammar
## ships them. `langDir` and `langSymbol` override the two derivations, for
## grammars whose upstream naming does not line up (`markdown_inline`).
##
## Still one module per grammar, deliberately: importing it is what links that
## parser, so a binary carries only the grammars it names.

import std/os
import ./capi, ./registry
export capi, registry

const vendorRoot* = tsVendorRoot
  ## Where the grammars live. Resolved in `capi`, so that the repo layout and an
  ## installed package both work.

proc orElse(a, b: string): string =
  ## `a` unless it is empty. A proc rather than an `if` in the const, because a
  ## template's `static` parameters do not survive one.
  if a.len > 0: a else: b

template vendored*(langName: static string;
                   langAliases: static seq[string] = @[];
                   langExts: static seq[string] = @[];
                   langShebangs: static seq[string] = @[];
                   langFilenames: static seq[string] = @[];
                   langDir: static string = "";
                   langSymbol: static string = "";
                   langSrcInclude: static bool = false) =
  ## Compile a vendored grammar in and register it.
  ##
  ## The parameters are prefixed because a template substitutes into field
  ## names too: a parameter named `name` would rewrite `Language(name: ...)`.
  const
    gd = vendorRoot / orElse(langDir, "tree-sitter-" & langName)
    csym = orElse(langSymbol, "tree_sitter_" & langName)
    hlQuery = staticRead(gd / "queries" / "highlights.scm")
    injQuery =
      when fileExists(gd / "queries" / "injections.scm"):
        staticRead(gd / "queries" / "injections.scm")
      else: ""

  when not fileExists(gd / "src" / "parser.c"):
    {.error: "grammar not vendored: run scripts/vendor.sh".}

  # For a scanner that includes a header from outside its own directory, which
  # then includes `tree_sitter/parser.h` relative to nothing in particular.
  when langSrcInclude:
    {.passC: "-I" & gd / "src".}

  {.compile: gd / "src" / "parser.c".}
  when fileExists(gd / "src" / "scanner.c"):
    {.compile: gd / "src" / "scanner.c".}

  # gensym: procs declared in a template are not hygienic by default, so a
  # second `vendored` in one module would collide.
  proc tsLang(): ptr TSLanguage {.gensym, importc: csym, cdecl.}

  register Language(
    name: langName, aliases: langAliases, exts: langExts,
    filenames: langFilenames, shebangs: langShebangs, lang: tsLang(),
    highlights: hlQuery, injections: injQuery)
