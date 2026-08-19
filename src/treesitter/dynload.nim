## Loading a grammar from a prebuilt shared object at runtime.
##
## Two ways to get a grammar into this library. Static vendoring (`langs/`) is
## right for a grammar small enough to commit and a binary that must work on a
## machine with nothing installed. This is right for the rest: grammars whose
## generated `parser.c` is too large to vendor comfortably -- tree-sitter-nim's
## is 40 MB -- and for tools that want whatever parsers the user already has.
##
## Shared objects carry no queries, so the highlights query comes separately.
## `loadFromNvim` finds both in an nvim-treesitter install; `loadLanguage` takes
## explicit paths when you ship or cache your own.
##
##   import treesitter, treesitter/dynload
##
##   let nim = registerFromNvim("nim", exts = @[".nim", ".nims", ".nimble"])
##   if nim == nil:
##     echo "no nim parser installed; .nim files will render plain"
##
## Note on nvim-treesitter's query files: they use Neovim's own predicates.
## `#has-ancestor?` and `#has-parent?` are implemented here, but `#lua-match?`
## and `#vim-match?` cannot be, and patterns carrying them are dropped --
## `unsupportedPredicates()` on the highlighter reports which. Some of those
## queries also expect language injection (nvim colours the body of a Nim doc
## comment as markdown), which this library does not do, so a doc comment shows
## its `##` styled and its text plain.

import std/[dynlib, os, strutils]
import ./capi, ./core, ./registry

type LanguageFn = proc(): ptr TSLanguage {.cdecl.}

const soExts =
  when defined(windows): [".dll"]
  elif defined(macosx): [".so", ".dylib"]  # nvim-treesitter builds .so on macOS
  else: [".so"]

proc loadLanguage*(soPath, name, highlights: string;
                   symbol = ""; aliases: seq[string] = @[];
                   exts: seq[string] = @[];
                   shebangs: seq[string] = @[]): Language =
  ## Raises TreeSitterError if the file, the symbol, or the ABI is wrong. It must
  ## raise rather than return a broken Language: calling into an ABI-mismatched
  ## parser crashes the process.
  let lib = loadLib(soPath)
  if lib == nil:
    raise newException(TreeSitterError, "cannot load " & soPath)
  let sym = if symbol.len > 0: symbol else: "tree_sitter_" & name.replace("-", "_")
  let fn = cast[LanguageFn](lib.symAddr(sym.cstring))
  if fn == nil:
    raise newException(TreeSitterError, soPath & ": no symbol '" & sym & "'")
  # The library is intentionally never unloaded: the TSLanguage it returns is
  # static data inside it and stays referenced by every tree we parse.
  let lang = fn()
  checkAbi(lang, soPath)
  result = Language(name: name, aliases: aliases, exts: exts,
                    shebangs: shebangs, lang: lang, highlights: highlights)

proc parserSearchDirs*(): seq[string] =
  ## Where to look for `<name>.so`, most specific first.
  ##
  ## `TREESITTER_PARSER_DIRS` (PATH-separated) comes first so a user can point at
  ## a cache the application manages itself.
  for d in getEnv("TREESITTER_PARSER_DIRS", "").split(PathSep):
    if d.len > 0 and dirExists(d): result.add d
  let home = getHomeDir()
  for p in [home / ".local/share/nvim/site/parser",
            home / ".local/share/nvim/lib/parser",
            home / ".local/share/nvim/lazy/nvim-treesitter/parser",
            home / ".config/helix/runtime/grammars",
            home / ".local/share/tree-sitter/parsers"]:
    if dirExists(p): result.add p

proc querySearchDirs*(): seq[string] =
  ## Where to look for `<name>/highlights.scm`.
  for d in getEnv("TREESITTER_QUERY_DIRS", "").split(PathSep):
    if d.len > 0 and dirExists(d): result.add d
  let home = getHomeDir()
  for p in [home / ".local/share/nvim/site/queries",
            home / ".local/share/nvim/lazy/nvim-treesitter/runtime/queries",
            home / ".config/helix/runtime/queries"]:
    if dirExists(p): result.add p

proc findParser*(name: string): string =
  ## Path to a parser shared object, or "" if none is installed.
  for d in parserSearchDirs():
    for ext in soExts:
      let c = d / (name & ext)
      if fileExists(c): return c
  ""

proc findHighlights*(name: string): string =
  ## Path to a highlights query, or "" if none is installed.
  for d in querySearchDirs():
    let c = d / name / "highlights.scm"
    if fileExists(c): return c
  ""

proc loadFromNvim*(name: string; aliases: seq[string] = @[];
                   exts: seq[string] = @[];
                   shebangs: seq[string] = @[]): Language =
  ## Best effort: find `<name>.so` and its highlights query in an installed
  ## editor runtime. Returns nil when either is missing, since "the user has no
  ## parser for this language" is a normal outcome; a parser that is present but
  ## unloadable still raises.
  let so = findParser(name)
  if so.len == 0: return nil
  let q = findHighlights(name)
  if q.len == 0: return nil
  loadLanguage(so, name, readFile(q), aliases = aliases, exts = exts,
               shebangs = shebangs)

proc registerFromNvim*(name: string; aliases: seq[string] = @[];
                       exts: seq[string] = @[];
                       shebangs: seq[string] = @[]): Language =
  ## `loadFromNvim` plus registration, so `findLanguage`/`detectLanguage` see it
  ## exactly as they see a compiled-in grammar. nil if nothing was found.
  result = loadFromNvim(name, aliases, exts, shebangs)
  if result != nil: register(result)
