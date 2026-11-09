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
## `unsupportedPredicates()` on the highlighter reports which.
##
## `injections.scm` is picked up alongside the highlights query when the install
## has one, so a Nim doc comment gets its body highlighted as markdown -- but
## only if the injected grammar is *also* registered. Register the ones you want
## reachable; an injected language that is missing just leaves that region with
## the host language's colouring.

import std/[dynlib, os, strutils]
import ./capi, ./core, ./registry

type LanguageFn = proc(): ptr TSLanguage {.cdecl.}

const soExts =
  when defined(windows):
    [".dll"]
  elif defined(macosx):
    [".so", ".dylib"] # nvim-treesitter builds .so on macOS
  else:
    [".so"]

proc loadLanguage*(
    soPath, name, highlights: string,
    symbol = "",
    aliases: seq[string] = @[],
    exts: seq[string] = @[],
    shebangs: seq[string] = @[],
): Language =
  ## Raises TreeSitterError if the file, the symbol, or the ABI is wrong. It must
  ## raise rather than return a broken Language: calling into an ABI-mismatched
  ## parser crashes the process.
  let lib = loadLib(soPath)
  if lib == nil:
    raise newException(TreeSitterError, "cannot load " & soPath)
  let sym =
    if symbol.len > 0:
      symbol
    else:
      "tree_sitter_" & name.replace("-", "_")
  let fn = cast[LanguageFn](lib.symAddr(sym.cstring))
  if fn == nil:
    raise newException(TreeSitterError, soPath & ": no symbol '" & sym & "'")
  # The library is intentionally never unloaded: the TSLanguage it returns is
  # static data inside it and stays referenced by every tree we parse.
  let lang = fn()
  checkAbi(lang, soPath)
  result = Language(
    name: name,
    aliases: aliases,
    exts: exts,
    shebangs: shebangs,
    lang: lang,
    highlights: highlights,
  )

proc existingDirs(envVar: string, defaults: openArray[string]): seq[string] =
  ## The PATH-separated dirs in `envVar`, then `defaults` under the home dir,
  ## keeping only those that exist.
  for d in getEnv(envVar, "").split(PathSep):
    if d.len > 0 and dirExists(d):
      result.add d
  let home = getHomeDir()
  for p in defaults:
    if dirExists(home / p):
      result.add home / p

proc parserSearchDirs*(): seq[string] =
  ## Where to look for `<name>.so`, most specific first.
  ##
  ## `TREESITTER_PARSER_DIRS` (PATH-separated) comes first so a user can point at
  ## a cache the application manages itself.
  existingDirs(
    "TREESITTER_PARSER_DIRS",
    [
      ".local/share/nvim/site/parser", ".local/share/nvim/lib/parser",
      ".local/share/nvim/lazy/nvim-treesitter/parser", ".config/helix/runtime/grammars",
      ".local/share/tree-sitter/parsers",
    ],
  )

proc querySearchDirs*(): seq[string] =
  ## Where to look for `<name>/highlights.scm`.
  existingDirs(
    "TREESITTER_QUERY_DIRS",
    [
      ".local/share/nvim/site/queries",
      ".local/share/nvim/lazy/nvim-treesitter/runtime/queries",
      ".config/helix/runtime/queries",
    ],
  )

proc findParser*(name: string): string =
  ## Path to a parser shared object, or "" if none is installed.
  for d in parserSearchDirs():
    for ext in soExts:
      let c = d / (name & ext)
      if fileExists(c):
        return c
  ""

proc findQuery(name, file: string): string =
  for d in querySearchDirs():
    let c = d / name / file
    if fileExists(c):
      return c
  ""

proc findHighlights*(name: string): string =
  ## Path to a highlights query, or "" if none is installed.
  findQuery(name, "highlights.scm")

proc findInjections*(name: string): string =
  ## Path to an injections query, or "" if the grammar ships none.
  findQuery(name, "injections.scm")

proc readNvimQuery*(name, file: string, inherited = false, depth = 0): string =
  ## The contents of `<name>/<file>`, with the queries it inherits prepended, or
  ## "" if the file is not installed.
  ##
  ## nvim-treesitter's query files often hold only a delta: `typescript`'s
  ## highlights begin `; inherits: ecma` and leave every keyword and string to
  ## that base. The modeline is a comma-separated list in the leading comment
  ## lines; a name in parentheses is pulled in only when this file is itself
  ## being inherited, as Neovim does. Bases come first so the inheriting file's
  ## own patterns, being later, win ties.
  let path = findQuery(name, file)
  if path.len == 0 or depth > 8: # depth: a cycle in the modelines
    return ""
  let own = readFile(path)
  for line in own.splitLines:
    if not line.startsWith(";"):
      break
    let body = line[1 .. ^1].strip
    if not body.startsWith("inherits:"):
      continue
    for item in body["inherits:".len .. ^1].split(','):
      var base = item.strip
      if base.startsWith("(") and base.endsWith(")"):
        if not inherited:
          continue
        base = base[1 .. ^2]
      if base.len > 0 and base != name:
        let q = readNvimQuery(base, file, inherited = true, depth = depth + 1)
        if q.len > 0:
          result.add q & "\n"
  result.add own

proc loadFromNvim*(
    name: string,
    aliases: seq[string] = @[],
    exts: seq[string] = @[],
    shebangs: seq[string] = @[],
): Language =
  ## Best effort: find `<name>.so` and its highlights query in an installed
  ## editor runtime. Returns nil when either is missing, since "the user has no
  ## parser for this language" is a normal outcome; a parser that is present but
  ## unloadable still raises.
  let so = findParser(name)
  if so.len == 0:
    return nil
  let q = readNvimQuery(name, "highlights.scm")
  if q.len == 0:
    return nil
  result =
    loadLanguage(so, name, q, aliases = aliases, exts = exts, shebangs = shebangs)
  result.injections = readNvimQuery(name, "injections.scm")

proc registerFromNvim*(
    name: string,
    aliases: seq[string] = @[],
    exts: seq[string] = @[],
    shebangs: seq[string] = @[],
): Language =
  ## `loadFromNvim` plus registration, so `findLanguage`/`detectLanguage` see it
  ## exactly as they see a compiled-in grammar. nil if nothing was found.
  result = loadFromNvim(name, aliases, exts, shebangs)
  if result != nil:
    register(result)
