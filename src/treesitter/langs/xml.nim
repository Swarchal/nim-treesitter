## tree-sitter-xml: vendored grammar, compiled in.
##
## Upstream ships xml and dtd in one repo, with the queries at the root rather
## than beside each parser; only xml is vendored.
import ../grammar

vendored "xml",
  langDir = "tree-sitter-xml/xml",   # kept nested: its scanner includes ../../common
  langSrcInclude = true,
  langExts = @[".xml", ".xsd", ".xsl", ".xslt", ".svg", ".plist"]
