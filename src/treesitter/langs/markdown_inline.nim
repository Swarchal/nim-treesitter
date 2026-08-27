## tree-sitter-markdown-inline: vendored grammar, compiled in.
##
## Registered under the name `markdown_inline` because that is the name the
## markdown grammar's `injections.scm` asks for. Rarely used on its own -- it
## parses the contents of a paragraph, not a document. It is also what colours
## markdown injected into doc comments by grammars such as Nim's.
##
## Upstream ships it in a subdirectory of the markdown repo, hence `langDir`.
import ../grammar

vendored "markdown_inline",
  langAliases = @["markdown-inline"],
  langDir = "tree-sitter-markdown-inline"
