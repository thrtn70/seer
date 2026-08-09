#!/usr/bin/env bash
# Render the Homebrew cask for a given version + sha256. With two arguments it prints to stdout;
# with a third it writes that path atomically instead. Commits nothing: the tap is a separate repo
# (thrtn70/homebrew-seer, Casks/seer.rb) and committing there is a publish step.
#
# Never redirect stdout onto the tap's Casks/seer.rb. The shell truncates the destination before
# this script starts, so any refusal below leaves the tap's only cask EMPTY — and the publish step
# runs 'git commit -am' and 'git push' on the next two lines, breaking 'brew install seer' for
# everyone. Pass the destination as the third argument: nothing is written unless every check
# passed, and the replacement is a single mv.
#
# The output path is resolved against YOUR cwd, not the repo root — the publish step runs this
# from inside the tap checkout.
#
# Render AFTER the final zip exists. The sha256 changes on every rebuild — even a rebuild of
# identical sources, because the signature is not byte-reproducible — which is exactly why this
# is a renderer and not a committed draft that can go stale.
set -euo pipefail
# Captured before the cd, because a relative third argument means a path in the caller's tree.
INVOCATION_DIR="$PWD"
cd "$(dirname "$0")/.."

VERSION="${1:?usage: render-cask.sh <version> <sha256> [output-path]}"
SHA="${2:?usage: render-cask.sh <version> <sha256> [output-path]}"
OUT_PATH="${3:-}"
TMPL="packaging/cask/seer.rb.tmpl"

fail() { echo "REFUSING: $*" >&2; exit 1; }

# An argument that is present but empty means the caller's destination variable did not expand.
# Falling back to stdout there would print the cask, exit 0, write nothing, and look exactly like
# success — while the next line of the publish step commits an unchanged cask.
[ "$#" -lt 3 ] || [ -n "$OUT_PATH" ] \
  || fail "output path argument is empty — the caller's destination variable did not expand"

test -f "$TMPL" || fail "missing $TMPL"
# A truncated or upper-cased sha fails the checksum for every single user who installs.
printf '%s' "$SHA" | grep -qE '^[0-9a-f]{64}$' \
  || fail "sha256 must be exactly 64 lowercase hex characters, got '${SHA}' (${#SHA} chars)"
printf '%s' "$VERSION" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$' \
  || fail "version must look like X.Y.Z, got '${VERSION}'"

# Everything the destination needs is checked here, alongside the other refusals, so that the
# write below is the only step left that can fail.
if [ -n "$OUT_PATH" ]; then
  case "$OUT_PATH" in
    /*) ;;
    *) OUT_PATH="$INVOCATION_DIR/$OUT_PATH" ;;
  esac
  DEST_DIR="$(dirname "$OUT_PATH")"
  test -d "$DEST_DIR" || fail "output directory does not exist: ${DEST_DIR}"
  test -w "$DEST_DIR" || fail "output directory is not writable: ${DEST_DIR}"
  # 'mv file dir' would silently drop the cask inside it instead of replacing anything.
  test ! -d "$OUT_PATH" || fail "output path is a directory: ${OUT_PATH}"
fi

OUT="$(sed -e "s/@@VERSION@@/${VERSION}/g" -e "s/@@SHA256@@/${SHA}/g" "$TMPL")"
case "$OUT" in
  *@@*) fail "an unsubstituted @@placeholder@@ remains in the rendered cask" ;;
esac

if [ -z "$OUT_PATH" ]; then
  printf '%s\n' "$OUT"
  exit 0
fi

# Beside the destination, not in $TMPDIR: mv is only atomic within one filesystem.
TMP="$(mktemp "${DEST_DIR}/.seer-cask.XXXXXX")"
trap 'rm -f "$TMP"' EXIT
printf '%s\n' "$OUT" > "$TMP"
chmod 644 "$TMP"   # mktemp gives 0600; this ends up as a checked-in repo file
mv -f "$TMP" "$OUT_PATH" || fail "could not replace ${OUT_PATH} (the destination is unchanged)"
trap - EXIT
echo "wrote ${OUT_PATH}" >&2
