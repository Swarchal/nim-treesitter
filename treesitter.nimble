version       = "0.1.0"
author        = "Scott Warchal"
description   = "tree-sitter syntax highlighting for Nim TUI applications"
license       = "MIT"
srcDir        = "src"
installExt    = @["nim"]
bin           = @[]
skipDirs      = @["tests", "examples"]

requires "nim >= 2.0.0"

task vendor, "Fetch the tree-sitter runtime and grammars":
  exec "./scripts/vendor.sh"

task test, "Run the test suite":
  exec "nim c -r --hints:off tests/tall.nim"

task adapter, "Run the nimtui adapter tests (needs nimtui; $NIMTUI_SRC or ../nim-tui/src)":
  # nimtui is not a hard dependency -- only treesitter/adapters/tui needs it.
  let src = if existsEnv("NIMTUI_SRC"): getEnv("NIMTUI_SRC") else: "../nim-tui/src"
  exec "nim c -r --hints:off --path:" & src & " tests/tnimtui.nim"

task hicat, "Build the example highlighting pager":
  exec "nim c -d:release --hints:off -o:bin/hicat examples/hicat.nim"
