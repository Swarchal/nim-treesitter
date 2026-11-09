## hicat -- cat with tree-sitter highlighting. Doubles as a smoke test.
##
##   hicat file.py [file.nim ...]
##   hicat --lang=json < data.json

import std/[os, strutils, terminal, tables]
import treesitter, treesitter/render, treesitter/dynload
# Importing a grammar module is what registers it.
import treesitter/langs/all # a pager takes whatever it is given

proc registerRuntimeLanguages() =
  ## Grammars too large to vendor come from an installed editor runtime, when
  ## there is one. Absent is not an error -- those filetypes render plain.
  discard registerFromNvim("nim", exts = @[".nim", ".nims", ".nimble"])
  # Every language Nim's queries inject into -- markdown, markdown_inline,
  # regex -- is bundled, so nothing else needs loading here.

var highlighters: Table[string, Highlighter]
  ## One per language, so queries compile once however many files are named.

proc highlighterFor(lang: Language): Highlighter =
  highlighters.withValue(lang.name, h):
    return h[]
  do:
    result = newHighlighter(lang)
    highlighters[lang.name] = result

proc emit(source, path, forced: string, level: ColorLevel) =
  var lang =
    if forced.len > 0:
      findLanguage(forced)
    else:
      detectLanguage(path, source)
  if lang == nil and forced.len > 0:
    # Named a language we have no compiled-in grammar for: try the machine's.
    lang = registerFromNvim(forced)
    if lang == nil:
      stderr.writeLine "no grammar for '" & forced & "' (compiled in or installed)"

  if lang == nil:
    stdout.write source.toAnsi(plainHighlights(source), level = level)
  else:
    let hl = highlighterFor(lang)
    var opts = defaultOptions()
    opts.maxErrorRatio = 0.3
    stdout.write source.toAnsi(hl.highlight(source, opts), level = level)
  stdout.write "\n"

when isMainModule:
  registerRuntimeLanguages()
  var
    files: seq[string]
    forced = ""
  for a in commandLineParams():
    if a.startsWith("--lang="):
      forced = a["--lang=".len .. ^1]
    elif a == "--list":
      for l in languages():
        echo l.name, "  ", l.exts.join(" ")
      quit 0
    elif a.startsWith("-"):
      echo "usage: hicat [--lang=NAME] [--list] [file ...]"
      quit 1
    else:
      files.add a

  var level = detectColorLevel()
  if not stdout.isatty and getEnv("HICAT_FORCE_COLOR", "") == "":
    level = clNone

  if files.len == 0:
    emit(stdin.readAll(), "", forced, level)
  else:
    for f in files:
      emit(readFile(f), f, forced, level)
