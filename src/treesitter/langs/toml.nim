## tree-sitter-toml: vendored grammar, compiled in.
##
## Also markdown's `+++` frontmatter injection.
import ../grammar

vendored "toml", langExts = @[".toml"], langFilenames = @["Cargo.lock"]
