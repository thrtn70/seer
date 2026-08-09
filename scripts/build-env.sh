# Shared build-output location. Sourced by the build, staging and update-verification scripts
# (all of which cd to the repo root first). Not executable on its own.
#
# Deliberately OUTSIDE the repo. This checkout lives under ~/Documents, which is covered by
# iCloud's "Desktop & Documents Folders" sync. iCloud's file provider stamps
# com.apple.FinderInfo onto files it syncs — including, within ~5-10 seconds, files codesign
# has just written — and codesign rejects any bundle carrying it:
#     resource fork, Finder information, or similar detritus not allowed
# Clearing the attributes first does not help: they come back before `codesign --verify`
# runs, so signing a bundle in place under ~/Documents is an unwinnable race. A signed
# bundle that fails verification would also fail Sparkle's own update validation.
#
# Override for a different location:  BUILD_DIR=/some/path scripts/build-app.sh
BUILD_DIR="${BUILD_DIR:-$HOME/Library/Caches/seer-build}"
