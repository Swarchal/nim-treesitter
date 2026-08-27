## tree-sitter-bash: vendored grammar, compiled in.
##
## Also the target of Dockerfile's `RUN` injection, when that grammar is loaded
## from a runtime.
import ../grammar

vendored "bash",
  langAliases = @["sh", "shell", "zsh"],
  langExts = @[".sh", ".bash", ".zsh", ".ksh"],
  langShebangs = @["bash", "sh", "zsh", "ksh", "dash"],
  langFilenames = @[".bashrc", ".bash_profile", ".bash_aliases", ".profile",
                    ".zshrc", ".zprofile", "PKGBUILD"]
