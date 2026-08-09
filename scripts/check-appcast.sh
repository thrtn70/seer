#!/usr/bin/env bash
# Validate a generated Sparkle appcast against the release it is supposed to describe.
#
# Standalone rather than inline in release-stage.sh so every assertion below can be pointed at a
# deliberately broken appcast and watched to fail. An assertion nobody has seen go RED is not an
# assertion — this repo has shipped three of those in Phase 13 and two in Phase 14.
#
# usage: check-appcast.sh <appcast.xml> <short-version> <bundle-version> <zip-bytes> <url-prefix> <bundle-ed-public-key>
set -euo pipefail

APPCAST="${1:?usage: check-appcast.sh <appcast> <short-version> <bundle-version> <zip-bytes> <url-prefix> <bundle-ed-public-key>}"
VERSION="${2:?missing <short-version>}"
BUNDLE_BUILD="${3:?missing <bundle-version>}"
ZIP_BYTES="${4:?missing <zip-bytes>}"
URL_PREFIX="${5:?missing <url-prefix>}"
# Required, not optional: a signing-key check the caller can omit is a check that quietly does not
# run, which is the exact failure mode this script exists to end. Omitting it aborts staging loudly.
#   BUNDLE_ED_KEY="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$APP/Contents/Info.plist")"
BUNDLE_ED_KEY="${6:?missing <bundle-ed-public-key> — PlistBuddy -c 'Print :SUPublicEDKey' <app>/Contents/Info.plist}"

fail() { echo "REFUSING: $*" >&2; exit 1; }

# No `cd` to the repo root here, unlike the rest of scripts/: the appcast path is an argument and
# may be relative to the caller's cwd. Reach the Sparkle tools off $0 instead.
SPARKLE_BIN="$(dirname "$0")/../vendor/sparkle-bin"

test -f "$APPCAST" || fail "missing appcast $APPCAST"
test -x "$SPARKLE_BIN/generate_keys" || fail "missing $SPARKLE_BIN/generate_keys (run scripts/fetch-sparkle.sh)"
test -x "$SPARKLE_BIN/sign_update" || fail "missing $SPARKLE_BIN/sign_update (run scripts/fetch-sparkle.sh)"

# xmllint, NOT plutil: the appcast is RSS/XML, and under `set -euo pipefail` a bare
# `plutil … && echo OK` neither prints nor aborts — the check would silently never run.
xmllint --noout "$APPCAST" 2>/dev/null || fail "appcast is not well-formed XML: $APPCAST"

xp() { xmllint --xpath "$1" "$APPCAST" 2>/dev/null || true; }
# sparkle:* are namespaced; match on local-name() so a changed prefix binding cannot quietly
# change the result. Sparkle 2.x emits them as <item> children; older layouts put them on
# <enclosure> as attributes. Accept either shape — but never accept empty.
sp() {
  local v
  v="$(xp "string(/rss/channel/item/*[local-name()='$1'])")"
  [ -n "$v" ] || v="$(xp "string(/rss/channel/item/enclosure/@*[local-name()='$1'])")"
  printf '%s' "$v"
}

ITEMS="$(xp 'count(/rss/channel/item)')"
[ "${ITEMS%.*}" = "1" ] || fail "appcast has ${ITEMS:-no} <item> entries, expected exactly 1"

SP_SHORT="$(sp shortVersionString)"
[ "$SP_SHORT" = "$VERSION" ] || fail "appcast shortVersionString is '$SP_SHORT', expected '$VERSION'"

SP_BUILD="$(sp version)"
[ "$SP_BUILD" = "$BUNDLE_BUILD" ] || fail "appcast sparkle:version is '$SP_BUILD', expected '$BUNDLE_BUILD'
  (the bundle's CFBundleVersion — Sparkle compares this, not the short version string)"

ENC_URL="$(xp 'string(/rss/channel/item/enclosure/@url)')"
case "$ENC_URL" in
  "${URL_PREFIX}"*) : ;;
  *) fail "appcast enclosure url is '$ENC_URL', expected it to start with '$URL_PREFIX'" ;;
esac

ENC_LEN="$(xp 'string(/rss/channel/item/enclosure/@length)')"
[ "$ENC_LEN" = "$ZIP_BYTES" ] || fail "appcast enclosure length is '$ENC_LEN' but the zip is ${ZIP_BYTES} bytes"

ED_SIG="$(xp "string(/rss/channel/item/enclosure/@*[local-name()='edSignature'])")"
[ ${#ED_SIG} -ge 40 ] || fail "appcast has no usable sparkle:edSignature (got ${#ED_SIG} chars) — was the EdDSA key reachable in the Keychain?"

# A signature of the right LENGTH says nothing about which key made it. generate_appcast pulls the
# private key out of the login Keychain by account name; a second or rotated Sparkle key sitting
# there would sign without complaint, and the resulting appcast is rejected by every installed
# copy — unrecoverably, since those users never trust a later feed either.
#
# sign_update --verify cannot be handed a public key. With --ed-key-file it wants the PRIVATE key
# (feeding it the public key just returns "failed to pass signing verification"); otherwise it
# reads the Keychain. So the cross-check is two links, and neither alone is worth anything:
#   (a) the Keychain's public key equals the SUPublicEDKey baked into the shipping bundle
#   (b) the enclosure signature verifies over the staged zip, under that same Keychain key
# Residual gap: (b) never sees the bundle's key bytes — it trusts (a) to have pinned them, and
# assumes the Keychain does not change between the two calls. generate_appcast, generate_keys and
# sign_update all use the default 'ed25519' account and none is passed --account, so a key signed
# under some other account shows up as (b) failing outright rather than passing silently.
#
# generate_keys -p can raise a Keychain prompt. Expected — build-app.sh already prompts during
# codesign — but it does mean staging is not an unattended step.
set +e
KEYCHAIN_ED_KEY="$("$SPARKLE_BIN/generate_keys" -p)"
KEY_STATUS=$?
set -e
[ "$KEY_STATUS" = 0 ] || fail "could not read the Sparkle public key from the Keychain (generate_keys -p exit ${KEY_STATUS}).
  The signing key behind this appcast is therefore UNVERIFIED."
[ "$KEYCHAIN_ED_KEY" = "$BUNDLE_ED_KEY" ] || fail "signing key mismatch — the Keychain holds
    ${KEYCHAIN_ED_KEY:-<empty>}
  but the bundle ships SUPublicEDKey
    ${BUNDLE_ED_KEY}
  This appcast is signed with a key no installed copy of Seer trusts."

# generate_appcast signed the file sitting next to the appcast; the enclosure url is that same file
# addressed on the download host. Verify against the local original.
ZIP_LOCAL="$(dirname "$APPCAST")/$(basename "$ENC_URL")"
test -f "$ZIP_LOCAL" || fail "enclosure names '$(basename "$ENC_URL")' but no such file sits next to
  $APPCAST — there is nothing to verify the signature against."
LOCAL_BYTES="$(stat -f%z "$ZIP_LOCAL")"
[ "$LOCAL_BYTES" = "$ZIP_BYTES" ] || fail "$ZIP_LOCAL is ${LOCAL_BYTES} bytes but the staged zip is ${ZIP_BYTES} —
  the signature would be verified over a different file than the one being released."

set +e
VERIFY_OUT="$("$SPARKLE_BIN/sign_update" --verify "$ZIP_LOCAL" "$ED_SIG" 2>&1)"
VERIFY_STATUS=$?
set -e
[ "$VERIFY_STATUS" = 0 ] || fail "sparkle:edSignature does not verify over $ZIP_LOCAL (sign_update exit ${VERIFY_STATUS}):
  ${VERIFY_OUT:-no output}"

DESC="$(xp 'string(/rss/channel/item/description)')"
[ ${#DESC} -ge 200 ] || fail "appcast <description> is ${#DESC} chars — the release notes did not embed"

echo "    1 item · ${SP_SHORT} (build ${SP_BUILD}) · signature verifies under the bundle's SUPublicEDKey ${BUNDLE_ED_KEY} · notes embedded (${#DESC} chars)"
