## tree-sitter-lua: vendored grammar, compiled in.
import ../grammar

vendored "lua",
  langExts = @[".lua"],
  langShebangs = @["lua", "luajit"]
