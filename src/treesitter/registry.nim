## Language registry.
##
## Each grammar lives in its own module under `langs/`, which compiles that
## grammar's `parser.c` and calls `register` at init. Importing only the
## languages you need is what keeps a small TUI from linking twenty parsers --
## there is no runtime plugin scan and no `-d:` list to keep in sync.

import std/[tables, strutils]
import ./capi, ./core

type
  Language* = ref object
    name*: string        ## canonical name, e.g. "python"
    aliases*: seq[string]
    exts*: seq[string]   ## with leading dot, e.g. @[".py", ".pyi"]
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
  checkAbi(l.lang, "register " & l.name)
  byName[l.name.toLowerAscii] = l
  for a in l.aliases: byName[a.toLowerAscii] = l
  ordered.add l

proc findLanguage*(name: string): Language =
  ## nil when unknown.
  byName.getOrDefault(name.toLowerAscii, nil)

proc languages*(): seq[Language] = ordered
