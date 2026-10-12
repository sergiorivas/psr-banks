# PSR Banks

macOS app to keep a library of PSR-E483 registration patches and assemble/export them as `.USR` setlists.

## Install

    brew install --cask sergiorivas/tap/psr-banks

The build is ad-hoc signed (not notarized); the cask strips the quarantine flag. If macOS still refuses to open it:
`xattr -cr "/Applications/PSR Banks.app"`.

## Develop

    swift test               # core logic, incl. byte-identical import → export of the example files
    ./build_app.sh --open    # builds "PSR Banks.app" and launches it

Library folder defaults to `~/Documents/PSR Banks Library` (change it from the "…" menu in the sidebar).

## Release

Bump `VERSION` and `CHANGELOG.md`, commit, then run `Scripts/publish_cask.sh`. It runs the tests, builds and zips the
app, tags `vX.Y.Z`, creates the GitHub release and updates the cask in the `homebrew-tap` repo.
