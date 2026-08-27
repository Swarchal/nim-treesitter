# nim-treesitter

tree-sitter powered syntax highlighting for Nim TUI applications.

Parses static text with real grammars — no hand-written lexer per language, no
regex approximation — and hands back **per-line, non-overlapping spans** that a
terminal renderer can draw directly. Grammars come from the existing
tree-sitter ecosystem: they ship pre-generated C, so nothing here writes or
generates a grammar.

Built to feed [nim-tui](https://github.com/swarchal/nim-tui): a highlighted
line becomes a `nimtui.Spans`, so `fit`, `elide`, `withScrollbar` and every
layout helper work on code exactly as they do on any other line.

```nim
import nimtui
import treesitter
import treesitter/adapters/tui
import treesitter/langs/python

let src = readFile("script.py")
let h = newHighlighter(findLanguage("python")).highlight(src)   # once per file
let styles = defaultSyntaxStyles().compile(h.captureNames)

for i in 0 ..< h.lineCount:                                     # per frame
  echo toSpans(src, h, i, styles, tabWidth = 4).fit(width).render()
```

Standalone, without nimtui:

```nim
import treesitter, treesitter/render, treesitter/langs/python

let src = readFile("script.py")
let h = newHighlighter(findLanguage("python")).highlight(src)
echo src.toAnsi(h)
```

## Setup

The tree-sitter runtime and the grammars are committed under `vendor/` at pinned
revisions, so a clone builds with no fetch step:

```sh
git clone https://github.com/swarchal/nim-treesitter && cd nim-treesitter
nimble test              # 52 tests
nimble adapter           # nimtui adapter tests, needs ../nim-tui/src or $NIMTUI_SRC
nimble hicat             # bin/hicat: cat with highlighting
```

`scripts/vendor.sh` is only needed to change or refresh a pin: it fetches each
revision listed in its `PINS` array (a fourth field on a pin names a
subdirectory, for repos shipping several grammars — tree-sitter-markdown ships
two) and prunes the checkout to what the build
reads — the runtime's `lib/`, and each grammar's C sources, bundled headers,
queries and licence. It removes each upstream's own `.git` as it goes, since a
nested one makes git record a gitlink and commit none of the contents. The
vendored revision is recorded in `vendor/<dir>/.rev`; a re-run is a no-op unless
a pin changed or you pass `--force`.

Point the build at a runtime checkout elsewhere with
`-d:tsVendorDir=/path/to/tree-sitter`.

`vendor/` is 40 MB checked out, but generated parser tables compress about 15:1,
so the repository itself is ~2.6 MB packed and that is what a clone downloads —
no compression scheme of our own is worth the build step it would cost.
Grammars whose `parser.c` is larger still are loaded at runtime instead — see
**Nim, and other large grammars** below.

## What it does and does not do

**Does:** one-shot parse, highlights queries with predicate evaluation, language
injection, overlap resolution, per-line spans, tab expansion, language
detection, ABI checking, a default palette plus one derived from a nimtui theme.

**Does not:** incremental reparsing (`ts_tree_edit`), rope/callback input, or
locals-aware highlighting (`locals.scm`). Those matter for an editor; this
library targets displaying text that is not being edited. The bindings in
`capi.nim` deliberately omit the editing API rather than expose something
half-wired.

### Injections

A region of one language embedded in another — markdown in a doc comment, regex
in `re"..."`, SQL in a query string, JS in `<script>` — is parsed with its own
grammar and highlighted from its own queries, driven by the grammar's
`queries/injections.scm`.

```nim
discard registerFromNvim("nim", exts = @[".nim"])
for name in ["markdown_inline", "regex"]:   # reachable targets
  discard registerFromNvim(name)
```

An injected language must be registered to be reachable; one that is missing
leaves its region with the host language's colouring rather than failing. Depth
is capped by `Options.maxInjectionDepth` (default 3; 0 disables). Supported
directives: `injection.language`, `injection.self`, `injection.parent`,
`injection.combined`, `injection.include-children` — and an `@injection.language`
capture that reads the target out of the source, so `sql"select ..."` picks its
own grammar.

Two details worth knowing. Named children of an `@injection.content` node are
masked out unless `injection.include-children` is set, matching Neovim, whose
query files are written against that default; it is what stops an interpolation
inside a template literal being parsed as part of the injected language. And
captures that carry an editor hint rather than a colour — `@spell`, `@nospell`,
`@conceal` — are dropped, because Neovim *stacks* highlight groups where this
resolves one capture per byte, so an unstyled capture arriving last would erase
the colour underneath instead of layering over it.

## Design notes

The parts that are easy to get subtly wrong, and what this does about them:

**Injected layers win over their host.** Layer is the dominant key in span
priority, so an injected grammar's captures beat the host's over the region it
was injected into, whatever the node sizes involved. Injected regions are parsed
with `ts_parser_set_included_ranges` over the *same* buffer rather than a
substring, so every layer's offsets share one coordinate system and merging is
just another paint pass.

**Rendering is line-oriented, because TUIs are.** A multi-line string literal
produces one span crossing several rows; re-clipping it on every redraw is
wasted work. `assemble` splits spans at newlines up front, so drawing a scroll
window is a slice. Byte offsets, not columns — the renderer converts.

**Precedence: for one node, the last matching pattern wins.** Query files depend
on this; tree-sitter-python's `highlights.scm` opens with a catch-all
`(identifier) @variable` that every later, more specific pattern overrides.
Nested captures beat the enclosing ones that contain them. Both fall out of a
paint buffer — one capture id per byte, painted lowest-priority first — which
costs 2 bytes per source byte transiently and avoids an interval tree.

**Predicates are evaluated, not ignored.** The C library hands you the raw steps
and expects you to filter matches yourself; skip that and every
`(#match? @const "^[A-Z]")` pattern matches everything. `#eq?`, `#match?`,
`#any-of?`, `#has-ancestor?`, `#has-parent?` and their `not-` forms are
implemented; directives (`#set!`, `#gsub!`) are metadata and ignored; anything else marks its pattern unsupported
and **drops its matches** rather than accepting unfiltered ones.
`unsupportedPredicates()` reports what was dropped. `#match?` uses `std/re`
(libpcre at runtime); `-d:tsNoRegex` drops that dependency and treats match
patterns as unsupported.

**Grammar ABI is checked before use.** A parser generated by a CLI outside the
runtime's supported window is a crash, not an error return, so `register` and
`loadLanguage` raise instead.

**Fragments parse badly by design.** tree-sitter recovers from malformed input,
but a snippet pulled out of context yields `ERROR` nodes and wrong colours.
`Options.maxErrorRatio` falls back to no highlighting past a threshold; it is off
by default (whole files should stay coloured) and worth setting to ~0.3 when
highlighting excerpts.

**Tabs are expanded by the renderer**, tracked across span boundaries so
alignment survives colouring. In the nimtui path this happens before handing
text over, because `Spans.add` flattens control characters to a single space.

## Adding a language

Grammar repos ship `src/parser.c` already generated, so this is vendoring plus
three lines. Add the repo to `PINS` in `scripts/vendor.sh`, then:

```nim
# src/treesitter/langs/go.nim
import ../grammar

vendored "go", langExts = @[".go"]
```

`vendored` derives the rest from the name: the directory `vendor/tree-sitter-go`,
the C entry point `tree_sitter_go`, and `scanner.c` and `injections.scm`
compiled in or read when the grammar ships them. `langDir` and `langSymbol`
override the two derivations, for grammars whose upstream naming does not line
up — `markdown_inline` lives in `vendor/tree-sitter-markdown-inline`. A grammar
that is not vendored fails at compile time with a pointer at `scripts/vendor.sh`
rather than at link time on a missing symbol.

Importing that module is what registers the language — nothing scans at runtime,
so a binary only links the grammars it imports. Bundled:

| module | language | notes |
| --- | --- | --- |
| `langs/bash` | bash | `.sh`, `.bash`, `.zsh`, `.ksh`, shebangs, `.bashrc`/`.profile`/`PKGBUILD` |
| `langs/c` | c | `.c`, `.h` — `.h` is claimed here only because cpp is not bundled |
| `langs/css` | css | `.css`; html's `<style>` injection target |
| `langs/go` | go | `.go`; `go.mod`/`go.sum` are separate grammars, not vendored |
| `langs/html` | html | injects `javascript` into `<script>`, `css` into `<style>` |
| `langs/java` | java | `.java` |
| `langs/javascript` | javascript | `.js`, `.jsx`, `.mjs`, `.cjs`, `node` shebang; parses JSX, though only upstream's plain `highlights.scm` is used |
| `langs/json` | json | `.json`, `.jsonl` |
| `langs/lua` | lua | `.lua`, `lua`/`luajit` shebangs |
| `langs/make` | make | `Makefile`, `GNUmakefile`, `.mk` |
| `langs/markdown` | markdown | block structure only |
| `langs/markdown_inline` | markdown_inline | emphasis, links, code spans |
| `langs/python` | python | `.py`, `.pyi`, `.pyw`, `python*` shebangs |
| `langs/regex` | regex | no extension of its own — an injection target for javascript and Nim |
| `langs/rust` | rust | `.rs` |
| `langs/toml` | toml | `.toml`, `Cargo.lock`; markdown's `+++` frontmatter |
| `langs/xml` | xml | `.xml`, `.xsd`, `.xsl`, `.svg`, `.plist` |
| `langs/yaml` | yaml | `.yaml`, `.yml`; markdown's `---` frontmatter |

`langs/all` imports every one of them, for a tool that highlights whatever it is
handed — both example programs use it. Not vendored, and loaded from a runtime
instead: `nim`, `cpp`, `ruby`, `typescript`, `tsx`.

Markdown is two grammars upstream, and this keeps that split: `langs/markdown`
alone colours headings, fences and lists but leaves paragraph text bare, and
`langs/markdown_inline` on its own is what a host grammar's injections reach for
(a Nim doc comment, for instance). Fenced code blocks inject the language named
in their info string, so ```` ```json ```` is highlighted as json when
`langs/json` is imported too.

Two caveats. Upstream javascript's `highlights.scm` uses `#is-not? local` on two
patterns (the `arguments`/`console`/`window`/… and `require` builtins); locals
tracking is not implemented here, so those patterns are dropped and those names
colour as ordinary variables — `unsupportedPredicates()` reports it. And the
markdown and xml grammars still use the older `text.*` capture names rather than
`markup.*`; the default palette carries both, at the same colours.

## Nim, and other large grammars

Nim's grammar is not vendored: its generated `parser.c` is 40 MB, which is more
than belongs in a committed `vendor/`. It is loaded at runtime instead, from a
parser already installed on the machine:

```nim
import treesitter, treesitter/dynload

let nim = registerFromNvim("nim", exts = @[".nim", ".nims", ".nimble"])
if nim == nil:
  echo "no nim parser installed; .nim files render plain"
```

`registerFromNvim` puts it in the registry, so `findLanguage("nim")` and
`detectLanguage("x.nim")` then see it exactly as they see a compiled-in grammar.
Search order is `$TREESITTER_PARSER_DIRS`, then nvim-treesitter's and Helix's
runtime directories (`parserSearchDirs()` / `querySearchDirs()` are public, and
`loadLanguage` takes explicit paths if you cache parsers yourself). Both example
programs do this for Nim.

Two caveats, since the queries then come from nvim-treesitter rather than
upstream:

- They use Neovim's own predicates. `#has-ancestor?` and `#has-parent?` are
  implemented here; `#lua-match?` and `#vim-match?` cannot be, and patterns
  carrying them are dropped — `unsupportedPredicates()` reports which.
- Their `injections.scm` is picked up too, so a Nim doc comment is highlighted as
  markdown and `re"..."` as a regex — provided those grammars are registered as
  well. `markdown_inline` is bundled, so importing `langs/markdown_inline` is
  enough for doc comments; `regex` still has to come from the runtime. `layerErrors()` reports any injected grammar whose queries would not
  compile; it is skipped rather than taking the host language down with it.

A grammar that is missing is a normal outcome, not an error: `detectLanguage`
returns nil and `plainHighlights` line-splits the text so it renders through the
same path uncoloured.

## Layout

| Module | Role |
| --- | --- |
| `treesitter/capi` | raw C bindings, imported from the real `api.h` |
| `treesitter/core` | ownership wrappers, ABI check, `errorRatio` |
| `treesitter/query` | query compilation, match iteration, predicates, directives |
| `treesitter/spans` | overlap resolution, per-line spans |
| `treesitter/registry` | language registry; `langs/*` register into it |
| `treesitter/detect` | extension and shebang detection |
| `treesitter/palette` | the syntax palette as data, capture-name fallback |
| `treesitter/highlight` | `newHighlighter`, `highlight`, injection layers, options |
| `treesitter/render` | standalone ANSI output (`treesitter/ansi`, `theme`) |
| `treesitter/adapters/tui` | `Highlights` → `nimtui.Spans` |
| `treesitter/dynload` | optional runtime `.so` loading |

`render` and `adapters/tui` are separate imports on purpose: nimtui already owns
`Style`, `hex` and colour-profile downgrade, and importing both styling layers
would collide.

## Examples

- `examples/hicat.nim` — `cat` with highlighting; stdin, `--lang=`, `--list`.
- `examples/nimtui/codeview.nim` — scrolling source viewer: line numbers,
  scrollbar, palette toggle. Shows the split that makes this cheap in a redraw
  loop — parse once on load, convert only visible rows per frame. Point it at a
  `.nim` file to exercise the runtime-loaded grammar.

## Licence

MIT. Vendored grammars and the tree-sitter runtime keep their own licences.
