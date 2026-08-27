## tree-sitter-python: vendored grammar, compiled in.
import ../grammar

vendored "python",
  langAliases = @["py"],
  langExts = @[".py", ".pyi", ".pyw"],
  langShebangs = @["python", "python2", "python3"]
