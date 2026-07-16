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
scripts/build-app.sh            # -> build/Seer.app (SeerCodeSign signed; pass '-' for ad-hoc)
scripts/release.sh 0.1.0        # -> zip + sha256, tag v0.1.0, gh release on thrtn70/seer
```

`build-app.sh` compiles `SeerAgent` (release/arm64), embeds `llama.framework` and the
`qwen2.5-1.5b-instruct-q4_k_m.gguf` model, fixes the rpath, then signs via `sign.sh`.

Acceptance check: `codesign -dr - build/Seer.app` must show
`identifier "app.seer.agent" and certificate leaf = H"…"` (NOT `cdhash`). The leaf hash is
identical across rebuilds — that's what keeps TCC grants alive. `spctl -a` rejecting is
expected (no notarization).

## Cask bump (repo: thrtn70/homebrew-seer, file Casks/seer.rb)

After `release.sh` prints the sha256, set `version` + `sha256` in `Casks/seer.rb`, commit, push.

## Install (users)

```bash
brew tap thrtn70/seer
brew install --cask seer        # postflight strips com.apple.quarantine
open -a Seer
```

Fallback if Gatekeeper still blocks: `xattr -dr com.apple.quarantine /Applications/Seer.app`
then right-click Seer.app → Open → Open.

## Notes / deferred

- No notarization (personal use). No Sparkle auto-update (deferred).
- R11 recovery (onboarding window re-prompts when a grant is missing) is retained as a
  backstop for fresh machines / revoked grants; with the stable identity it rarely triggers.
