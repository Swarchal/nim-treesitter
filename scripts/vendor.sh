#!/usr/bin/env bash
# Fetch the tree-sitter runtime and the grammars we vendor, at pinned revisions.
#
# Grammars ship pre-generated src/parser.c, so no node or tree-sitter CLI is
# needed -- this only downloads and prunes.
#
# vendor/ is committed, so what lands there is the minimal set needed to build:
# the runtime's lib/, and each grammar's C sources, bundled headers, queries and
# licence. Everything else (each upstream's own .git, test corpora, docs, Cargo
# and node packaging) is dropped -- a nested .git in particular would make git
# record a gitlink and commit none of the contents.
#
# Pinned revisions are recorded in vendor/<dir>/.rev, which is also how a re-run
# knows what is already correct. Pass --force to refetch regardless.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
vendor="$root/vendor"
force=0
[ "${1:-}" = "--force" ] && force=1
mkdir -p "$vendor"

# repo-url                                              dir                        tag-or-sha  [subdir]
# A fourth field names the grammar's subdirectory inside the checkout, for repos
# that ship several grammars (tree-sitter-markdown does). The licence is still
# taken from the repo root when the subdirectory has none.
PINS=(
  "https://github.com/tree-sitter/tree-sitter                    tree-sitter               v0.26.12"
  "https://github.com/tree-sitter/tree-sitter-json               tree-sitter-json          254c42a6476413b776221e03982ac8ae159eeb72"
  "https://github.com/tree-sitter/tree-sitter-python             tree-sitter-python        26855eabccb19c6abf499fbc5b8dc7cc9ab8bc64"
  "https://github.com/tree-sitter/tree-sitter-html               tree-sitter-html          v0.23.2"
  "https://github.com/tree-sitter/tree-sitter-javascript         tree-sitter-javascript    v0.25.0"
  "https://github.com/tree-sitter-grammars/tree-sitter-markdown  tree-sitter-markdown      v0.5.3  tree-sitter-markdown"
  "https://github.com/tree-sitter-grammars/tree-sitter-markdown  tree-sitter-markdown-inline  v0.5.3  tree-sitter-markdown-inline"
  "https://github.com/tree-sitter/tree-sitter-css                 tree-sitter-css           v0.25.0"
  # Newer than the v1.0.0 tag on purpose: that tag's generated parser.c uses an
  # angle-bracket include for tree_sitter/parser.h, which needs its own -I.
  "https://github.com/tree-sitter/tree-sitter-regex               tree-sitter-regex         b2ac15e27fce703d2f37a79ccd94a5c0cbe9720b"
  "https://github.com/tree-sitter-grammars/tree-sitter-toml       tree-sitter-toml          v0.7.0"
  "https://github.com/tree-sitter-grammars/tree-sitter-yaml       tree-sitter-yaml          v0.7.2"
  "https://github.com/tree-sitter-grammars/tree-sitter-lua        tree-sitter-lua           v0.5.0"
  "https://github.com/tree-sitter-grammars/tree-sitter-xml        tree-sitter-xml           v0.7.0  xml"
  "https://github.com/tree-sitter-grammars/tree-sitter-make       tree-sitter-make          v1.1.1"
  "https://github.com/tree-sitter/tree-sitter-go                  tree-sitter-go            v0.25.0"
  "https://github.com/tree-sitter/tree-sitter-java                tree-sitter-java          v0.23.5"
  "https://github.com/tree-sitter/tree-sitter-c                   tree-sitter-c             v0.24.2"
  "https://github.com/tree-sitter/tree-sitter-rust                tree-sitter-rust          v0.24.2"
  "https://github.com/tree-sitter/tree-sitter-bash                tree-sitter-bash          v0.25.1"
)

# Keep only what the build reads. Paths are relative to the checkout root.
keep_runtime=(lib/src lib/include LICENSE)
keep_grammar=(src queries LICENSE LICENSE.md LICENSES)

copy_kept() {
  local src="$1" dest="$2"; shift 2
  local p
  for p in "$@"; do
    [ -e "$src/$p" ] || continue
    mkdir -p "$dest/$(dirname "$p")"
    cp -R "$src/$p" "$dest/$(dirname "$p")/"
  done
}

prune_grammar_src() {
  # Grammar src/ carries generated JSON the compiler never reads; parser.c is
  # already large enough without it.
  local dest="$1"
  rm -f "$dest/src/grammar.json" "$dest/src/node-types.json" \
        "$dest/src/grammar.json.license" "$dest/src/node-types.json.license"
}

fetch() {
  local url="$1" dir="$2" rev="$3" sub="${4:-}"
  local dest="$vendor/$dir"
  local revfile="$dest/.rev"

  if [ "$force" -eq 0 ] && [ -f "$revfile" ] && [ "$(cat "$revfile")" = "$rev" ]; then
    echo "== $dir: $rev already vendored"
    return
  fi

  echo "== $dir: fetching $rev"
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  git init -q "$tmp"
  git -C "$tmp" remote add origin "$url"
  git -C "$tmp" fetch -q --depth 1 origin "$rev"
  git -C "$tmp" checkout -q FETCH_HEAD
  local sha
  sha="$(git -C "$tmp" rev-parse HEAD)"

  rm -rf "$dest"
  mkdir -p "$dest"
  if [ "$dir" = "tree-sitter" ]; then
    copy_kept "$tmp" "$dest" "${keep_runtime[@]}"
  else
    # A grammar in a subdirectory is normally flattened into $dest, so every
    # vendored grammar has the same shape. The exception is a scanner that
    # includes the repo's shared "../../common/...": flattening would break that
    # relative path, so the upstream layout is kept and the module points at
    # `<dir>/<sub>` instead.
    local base="$tmp" inner="$dest"
    if [ -n "$sub" ]; then
      base="$tmp/$sub"
      if grep -qr '\.\./\.\./common' "$base/src" 2>/dev/null; then
        inner="$dest/$sub"
        mkdir -p "$inner"
        cp -R "$tmp/common" "$dest/"
      fi
    fi
    copy_kept "$base" "$inner" "${keep_grammar[@]}"
    # A multi-grammar repo may keep the queries at the root, one directory per
    # grammar (tree-sitter-xml) rather than beside each parser.
    if [ ! -d "$inner/queries" ]; then
      if [ -n "$sub" ] && [ -d "$tmp/queries/$sub" ]; then
        mkdir -p "$inner/queries" && cp -R "$tmp/queries/$sub/." "$inner/queries/"
      elif [ -d "$tmp/queries" ]; then
        cp -R "$tmp/queries" "$inner/"
      fi
    fi
    # Multi-grammar repos keep the one licence at the repo root.
    if [ ! -e "$dest/LICENSE" ] && [ ! -e "$dest/LICENSE.md" ]; then
      copy_kept "$tmp" "$dest" LICENSE LICENSE.md LICENSES
    fi
    prune_grammar_src "$inner"
  fi
  echo "$rev" > "$revfile"
  echo "$url $sha" > "$dest/.source"
  echo "   $sha  $(du -sh "$dest" | cut -f1)"
}

for pin in "${PINS[@]}"; do
  # shellcheck disable=SC2086
  set -- $pin
  fetch "$1" "$2" "$3" "${4:-}"
done

echo
echo "Vendored into $vendor ($(du -sh "$vendor" | cut -f1))"
