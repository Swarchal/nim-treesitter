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

# repo-url                                        dir                 tag-or-sha
PINS=(
  "https://github.com/tree-sitter/tree-sitter             tree-sitter             v0.26.12"
  "https://github.com/tree-sitter/tree-sitter-json        tree-sitter-json        254c42a6476413b776221e03982ac8ae159eeb72"
  "https://github.com/tree-sitter/tree-sitter-python      tree-sitter-python      26855eabccb19c6abf499fbc5b8dc7cc9ab8bc64"
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
  local url="$1" dir="$2" rev="$3"
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
    copy_kept "$tmp" "$dest" "${keep_grammar[@]}"
    prune_grammar_src "$dest"
  fi
  echo "$rev" > "$revfile"
  echo "$url $sha" > "$dest/.source"
  echo "   $sha  $(du -sh "$dest" | cut -f1)"
}

for pin in "${PINS[@]}"; do
  # shellcheck disable=SC2086
  set -- $pin
  fetch "$1" "$2" "$3"
done

echo
echo "Vendored into $vendor ($(du -sh "$vendor" | cut -f1))"
