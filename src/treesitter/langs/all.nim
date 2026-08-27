## Every bundled grammar, for tools that highlight whatever they are handed.
##
## Importing this links all of them -- around 40 MB of generated parser tables
## compiled in. An application that knows its filetypes should import just those
## modules instead; that selectivity is the point of the per-grammar split.
{.used.}  # imported for the registrations alone, never for a symbol

import ./json, ./python, ./html, ./javascript, ./markdown, ./markdown_inline,
       ./css, ./regex, ./toml, ./yaml, ./lua, ./xml, ./make, ./go, ./java,
       ./c, ./rust, ./bash
