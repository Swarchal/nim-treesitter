## Language registry.
##
## Each grammar lives in its own module under `langs/`, which compiles that
## grammar's `parser.c` and calls `register` at init. Importing only the
## languages you need is what keeps a small TUI from linking twenty parsers --
## there is no runtime plugin scan and no `-d:` list to keep in sync.

import std/[tables, strutils]
import ./capi, ./core

type Language* = ref object
  name*: string ## canonical name, e.g. "python"
  aliases*: seq[string]
  exts*: seq[string] ## with leading dot, e.g. @[".py", ".pyi"]
  filenames*: seq[string]
    ## whole basenames, e.g. @["Makefile"], for the
    ## files that carry no useful extension
  shebangs*: seq[string] ## interpreter basenames, e.g. @["python", "python3"]
  lang*: ptr TSLanguage
  highlights*: string ## contents of queries/highlights.scm
  injections*: string ## optional, empty when the grammar ships none

var
  byName: Table[string, Language]
  ordered: seq[Language]

proc register*(l: Language) =
  ## Raises if the grammar's ABI is outside the runtime's supported range, at
  ## import time rather than on first parse.
  ##
  ## Registering a name that is already registered replaces that language
  ## everywhere -- `findLanguage`, detection and `languages()` -- so an installed
  ## parser can take over from a compiled-in one. The old language's aliases go
  ## with it.
  checkAbi(l.lang, "register " & l.name)
  let key = l.name.toLowerAscii
  let old = byName.getOrDefault(key, nil)
  if old != nil and old.name.toLowerAscii == key:
    for a in old.aliases:
      if byName.getOrDefault(a.toLowerAscii, nil) == old:
        byName.del a.toLowerAscii
    let i = ordered.find(old)
    if i >= 0:
      ordered[i] = l
  else:
    ordered.add l
  byName[key] = l
  for a in l.aliases:
    byName[a.toLowerAscii] = l

proc findLanguage*(name: string): Language =
  ## nil when unknown.
  byName.getOrDefault(name.toLowerAscii, nil)

proc languages*(): seq[Language] =
  ordered
