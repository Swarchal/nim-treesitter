## Guessing a language from a filename or content.
##
## An editor is told the filetype; a highlighting library gets handed a blob, so
## this has to exist somewhere. Filename first, then extension, then shebang,
## then nil.

import std/[os, strutils]
import ./registry

proc byExtension*(path: string): Language =
  let ext = path.splitFile.ext.toLowerAscii
  if ext.len == 0:
    return nil
  for l in languages():
    for e in l.exts:
      if cmpIgnoreCase(e, ext) == 0:
        return l
  nil

proc byFilename*(path: string): Language =
  ## Whole-basename match, for the files whose extension says nothing useful --
  ## `Makefile`, `.bashrc`. Case-sensitive, since `makefile` and `Makefile` are
  ## both spellings a project picks deliberately and both are listed.
  let base = path.extractFilename
  if base.len == 0:
    return nil
  for l in languages():
    if base in l.filenames:
      return l
  nil

proc byShebang*(source: string): Language =
  if not source.startsWith("#!"):
    return nil
  let nl = source.find('\n')
  let line = source[2 ..< (if nl < 0: source.len else: nl)]
  let words = line.splitWhitespace()
  if words.len == 0:
    return nil
  # "/usr/bin/env python3" -> python3; "/bin/sh" -> sh
  var interp = words[0].extractFilename
  if interp == "env" and words.len > 1:
    interp = words[1].extractFilename
  for l in languages():
    if interp == l.name or interp in l.shebangs:
      return l
  nil

proc detectLanguage*(path = "", source = ""): Language =
  ## nil means "highlight as plain text" -- a normal outcome, not an error.
  if path.len > 0:
    # Filename before extension: `Makefile.am` should not be read as an `.am`.
    result = byFilename(path)
    if result != nil:
      return
    result = byExtension(path)
    if result != nil:
      return
  if source.len > 0:
    result = byShebang(source)
