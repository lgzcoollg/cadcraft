#!/usr/bin/env bash
# Check that a running CADCraft web server serves the build the way browsers need it: the page
# revalidated, the content-hashed .js and .wasm cached forever, typed text/javascript and
# application/wasm, and the .wasm gzipped. It runs against any URL, so it covers the Docker image
# built from this directory, a self-hosted nginx, and a host this repository has never seen.
#
# Usage: packaging/docker/smoke-test.sh [base-url]     # default http://127.0.0.1:8771
#
# Needs: curl. Exit code 0 means the site serves correctly; anything else prints why not.
set -euo pipefail

BASE="${1:-http://127.0.0.1:8771}"
BASE="${BASE%/}"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

ok() {
  echo "ok   $*"
}

# header <url> <name> -> the last value of that response header, empty when it is not sent.
header() {
  local url="$1" name="$2" lower
  lower="$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]')"
  curl -fsS -D - -o /dev/null -H 'Accept-Encoding: gzip' "$url" |
    tr -d '\r' |
    awk -F': ' -v want="$lower" 'tolower($1) == want { print $2 }' |
    tail -n 1
}

# want_header <url> <name> <substring>
want_header() {
  local got
  got="$(header "$1" "$2" || true)"
  case "$got" in
    *"$3"*) ok "$1: $2: $got" ;;
    *) fail "$1: $2 is '${got:-<missing>}', expected it to contain '$3'" ;;
  esac
}

# The page itself: always revalidated, so a new release is picked up without a hard refresh.
want_header "$BASE/" Content-Type text/html
want_header "$BASE/" Cache-Control no-cache

# --compressed: nginx gzips the page, and the URLs have to be read out of the decoded text.
index="$(curl -fsS --compressed "$BASE/")"

# Every path the page quotes. Trunk writes attribute values and an inline module script, in both
# quote styles, and index.html is the authority on the .wasm too: the fallback name inside
# wasm-bindgen's glue is never fetched, because trunk hands init() the real, hashed path.
urls="$(
  printf '%s' "$index" |
    grep -oE "['\"][^'\"]*\.(wasm|js|css|json|png|svg|ico|webp|woff2?)['\"]" |
    tr -d "'\"" |
    sort -u || true
)"

wasm=0
js=0
external=0
while IFS= read -r url; do
  [ -n "$url" ] || continue
  case "$url" in
    http://*|https://*|//*|data:*)
      external=$((external + 1))
      continue
      ;;
  esac

  path="${url#./}"
  code="$(curl -fsS -o /dev/null -w '%{http_code}' "$BASE/$path" || true)"
  # Trunk inlines nothing, so every relative path in index.html must be a file next to it.
  [ "$code" = "200" ] || fail "$BASE/$path returned ${code:-no response}"

  case "$path" in
    *.wasm)
      wasm=$((wasm + 1))
      want_header "$BASE/$path" Content-Type application/wasm
      want_header "$BASE/$path" Cache-Control immutable
      want_header "$BASE/$path" Content-Encoding gzip
      ;;
    *.js)
      js=$((js + 1))
      want_header "$BASE/$path" Content-Type text/javascript
      want_header "$BASE/$path" Cache-Control immutable
      ;;
    *)
      ok "$BASE/$path (200)"
      ;;
  esac
done <<<"$urls"

[ "$js" -gt 0 ] || fail "$BASE/ loads no .js — is the site built (see packaging/docker/README.md)?"
[ "$wasm" -gt 0 ] || fail "$BASE/ loads no .wasm — is the site built (see packaging/docker/README.md)?"

echo "PASS: $BASE/ serves index.html, $js .js and $wasm .wasm correctly ($external external URL(s) skipped)"
