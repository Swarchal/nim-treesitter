## Guessing a language from a filename or content.
##
## An editor is told the filetype; a highlighting library gets handed a blob, so
## this has to exist somewhere. Extension first, then shebang, then nil.

import std/[os, strutils]
import ./registry

proc byExtension*(path: string): Language =
  let ext = path.splitFile.ext.toLowerAscii
  if ext.len == 0: return nil
  for l in languages():
    for e in l.exts:
      if e.toLowerAscii == ext: return l
  nil

proc byShebang*(source: string): Language =
  if not source.startsWith("#!"): return nil
  let nl = source.find('\n')
  let line = source[2 ..< (if nl < 0: source.len else: nl)]
  var words: seq[string]
  for w in line.splitWhitespace(): words.add w
  if words.len == 0: return nil
  # "/usr/bin/env python3" -> python3; "/bin/sh" -> sh
  var interp = words[0].extractFilename
  if interp == "env" and words.len > 1: interp = words[1].extractFilename
  for l in languages():
    if interp == l.name: return l
    for s in l.shebangs:
      if interp == s: return l
  nil

proc detectLanguage*(path = "", source = ""): Language =
  ## nil means "highlight as plain text" -- a normal outcome, not an error.
  if path.len > 0:
    result = byExtension(path)
    if result != nil: return
  if source.len > 0:
    result = byShebang(source)
