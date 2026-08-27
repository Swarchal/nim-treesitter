## tree-sitter-yaml: vendored grammar, compiled in.
##
## Also markdown's `---` frontmatter injection.
import ../grammar

vendored "yaml", langAliases = @["yml"], langExts = @[".yaml", ".yml"]
