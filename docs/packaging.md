# Seer Packaging & Distribution

Seer ships as `Seer.app` via a personal Homebrew tap. Personal use, self-signed (no Apple
Developer ID / no notarization).

## One-time: self-signed code-signing certificate

Why: a stable code identity keeps Accessibility + Input Monitoring grants alive across
rebuilds (ad-hoc signing's `cdhash` changes every build and silently drops grants).

Keychain Access → Certificate Assistant → Create a Certificate:
- Name `SeerCodeSign`, Identity Type **Self-Signed Root**, Certificate Type **Code Signing**.
- Verify: `security find-identity -p codesigning` lists `SeerCodeSign`. It will show
  `CSSMERR_TP_NOT_TRUSTED` — that's fine; signing doesn't require trust. (Don't use `-v`:
  it filters to *trusted* identities and shows "0 valid identities" for a self-signed cert.)
- On the first sign, macOS asks "codesign wants to sign using key SeerCodeSign" —
  click **Always Allow** so future builds sign without prompting.

## Build → sign → release

```bash
scripts/build-app.sh                              # -> $BUILD_DIR/Seer.app (SeerCodeSign signed; '-' for ad-hoc)
scripts/release-stage.sh 0.2.0                    # -> zip + sha256 + signed appcast, all local
```

Publishing the tag and the GitHub release is a separate, maintainer-only step; it needs staged
artifacts and write access to the repo, so it is not part of a build from source.

`build-app.sh` compiles `SeerAgent` (release/arm64), embeds `llama.framework` and
`Sparkle.framework`, fixes the rpath, strips extended attributes, then signs via `sign.sh`.

Staging and publishing are deliberately separate programs. `release-stage.sh` touches no network:
it re-checks that the bundle really is a production build (feed URL matches `packaging/Info.plist`,
version matches the argument, no `NSAppTransportSecurity` exception, `codesign --verify --strict`
passes), zips it, generates the EdDSA-signed appcast with the release notes embedded, and then
validates the appcast it just produced via `check-appcast.sh` — item count, `sparkle:version`
against the bundle's `CFBundleVersion`, short version, enclosure URL prefix and byte length,
signature, and a non-empty description.

Exactly one script publishes, and it refuses unless every guard holds: the staged zip's sha256 still
matches what staging recorded and the appcast re-validates against it, the commit being tagged is
already on the public remote and its `packaging/Info.plist` declares the version being published
(`gh release create --target` makes the tag server-side, so a local-only commit would produce a tag
nobody can fetch), the build number strictly beats the last published release, and an explicit
confirmation variable is set. That script is maintainer-only and is not part of this repository.

Release notes live in `packaging/release-notes/<version>.html` as a fragment — no DOCTYPE, no
`<body>` — which is what makes `generate_appcast` embed them as CDATA rather than link out.

### The model is not bundled

The `qwen2.5-1.5b-instruct-q4_k_m.gguf` model (~1.1 GB) is **not** in the app. Seer downloads
it on first run to:

```
~/Library/Application Support/Seer/models/qwen2.5-1.5b-instruct-q4_k_m.gguf
```

The download is checksum-verified against `ModelSpec.sha256`
([Sources/SeerSupport/ModelSpec.swift](../Sources/SeerSupport/ModelSpec.swift)) before it is
moved into place, so a truncated or tampered file can never become the installed model. If the
engine later fails to load it, the file is quarantined as `.corrupt` and re-downloaded rather
than crash-looping the app.

This keeps the signed bundle around **14 MB instead of ~1.1 GB**, so a Sparkle update is a
small download and never re-fetches a model the user already has (the path is
version-independent).

`scripts/fetch-model.sh` still populates `vendor/` for the dev flow (`swift run SeerAgent`,
`SeerBench`, the probes) and now verifies the same pinned checksum — `ModelSpecTests` asserts
the script and the Swift constants cannot drift apart.

To skip the download on a dev machine that already has the model:

```bash
mkdir -p ~/Library/Application\ Support/Seer/models
ditto vendor/qwen2.5-1.5b-instruct-q4_k_m.gguf \
      ~/Library/Application\ Support/Seer/models/qwen2.5-1.5b-instruct-q4_k_m.gguf
```

### Where the build output goes

`BUILD_DIR` defaults to `~/Library/Caches/seer-build` — **outside the repo on purpose**, and
defined once in `scripts/build-env.sh` (sourced by the build, staging and update-verification
scripts). This checkout lives under `~/Documents`, which
iCloud's "Desktop & Documents Folders" sync covers; its file provider stamps
`com.apple.FinderInfo` onto files it syncs, including files `codesign` has just written, and
`codesign` rejects any bundle carrying it:

```
resource fork, Finder information, or similar detritus not allowed
```

Clearing the attributes first does not help — they return within seconds, before
`codesign --verify` runs. A signed bundle that fails verification would also fail Sparkle's
update validation. Building outside the synced tree avoids the race entirely. Override with
`BUILD_DIR=/some/path scripts/build-app.sh`.

Acceptance check: `codesign -dr - "$BUILD_DIR/Seer.app"` must show
`identifier "app.seer.agent" and certificate leaf = H"…"` (NOT `cdhash`). The leaf hash is
identical across rebuilds — that's what keeps TCC grants alive. `spctl -a` rejecting is
expected (no notarization).

## Cask bump (repo: thrtn70/homebrew-seer, file Casks/seer.rb)

`packaging/cask/seer.rb.tmpl` is the source of truth. `scripts/render-cask.sh <version> <sha256>`
renders it to stdout; given a third argument it writes that path atomically instead. Render it
**after** the final zip exists, then commit and push:

```bash
scripts/render-cask.sh 0.2.0 "$(cat "$BUILD_DIR"/Seer-0.2.0.zip.sha256)" Casks/seer.rb
```

Pass the destination as an argument — never redirect stdout onto it. `>` truncates the file before
the renderer starts, so any refusal leaves the tap's only cask empty, two lines before a
`git commit -am` and a `git push`.

It is a renderer rather than a checked-in draft because the sha256 changes on **every** rebuild —
even a rebuild of identical sources, since the signature is not byte-reproducible. A cask carrying
a stale sha fails the checksum for everyone who installs it.

The cask sets `auto_updates true`: Seer updates itself through Sparkle, so Homebrew should not
treat a newer version as something it must install over the top.

## Install (users)

```bash
brew tap thrtn70/seer
brew install --cask seer        # postflight strips com.apple.quarantine
open -a Seer
```

Fallback if Gatekeeper still blocks: `xattr -dr com.apple.quarantine /Applications/Seer.app`
then right-click Seer.app → Open → Open.

## Auto-update (Sparkle)

Seer bundles [Sparkle](https://sparkle-project.org) 2.9.4, vendored like llama:

```bash
scripts/fetch-sparkle.sh        # -> vendor/Sparkle.xcframework + vendor/sparkle-bin/
```

`build-app.sh` embeds `Sparkle.framework` and deletes its `XPCServices` (needed only by
sandboxed apps); `sign.sh` re-signs it inside-out with `SeerCodeSign` — **never** with
`--deep` or `-o runtime`. Hardened runtime would enable Library Validation, which matches on
Team ID; a self-signed cert has none, so the app would fail to load its own framework after
the first self-update.

Updates verify against the EdDSA key in `SUPublicEDKey` and against the app's own Designated
Requirement — no Apple Developer ID or notarization involved. Because the DR is stable, the
Accessibility / Input Monitoring grants survive an update.

One-time key setup (already done; repeat only on a new machine):

```bash
vendor/sparkle-bin/generate_keys      # private key -> login Keychain
vendor/sparkle-bin/generate_keys -p   # public key  -> SUPublicEDKey in Info.plist

# OFFLINE BACKUP — note the path is OUTSIDE the repo, so a stray commit cannot leak it.
# Move it into a password manager / encrypted backup, then delete the file.
vendor/sparkle-bin/generate_keys -x ~/Desktop/seer-sparkle-ed25519.key
```

Never write the private key inside the working tree. (`*.key` is gitignored as a safety net,
but the exported file should not live in the repo at all.)

The private key is unrecoverable if the Keychain is lost, and without it no update that
existing installs will accept can ever be signed again.

`release-stage.sh` writes a signed `$BUILD_DIR/updates/appcast.xml` with the release notes from
`packaging/release-notes/<version>.html` embedded. **Publishing it** — hosting the feed at
`https://thrtn70.github.io/seer/appcast.xml`, the `SUFeedURL` baked into Info.plist — and bumping
the cask are separate deployment steps, deliberately not automated by any script that runs during
a build.

To exercise a real update locally: `scripts/verify-update.sh` (builds two versions, serves a
signed local appcast, prints the manual steps).

## Notes / deferred

- No notarization (personal use).
- R11 recovery (onboarding window re-prompts when a grant is missing) is retained as a
  backstop for fresh machines / revoked grants; with the stable identity it rarely triggers.
