#!/usr/bin/env bash
# Publishes the version in VERSION as a prebuilt-binary Homebrew Cask (same
# approach as the Listo project): tests, builds an ad-hoc-signed PSR Banks.app,
# zips it, tags vX.Y.Z, pushes, creates the GitHub release with the zip, and
# regenerates Casks/psr-banks.rb in the shared tap.
#
# No Developer ID / notarization: the cask's postflight strips the Gatekeeper
# quarantine flag with `xattr -cr`.
#
# Versioning is hands-off (same as Listo): Scripts/version.sh takes the next patch
# after the latest vX.Y.Z tag, and this script creates + pushes that tag. Pass a
# version to override it (e.g. for a minor bump). Add a "## X.Y.Z" section to
# CHANGELOG.md first if you want it used as the release notes. Env vars:
#   PSRBANKS_GITHUB_REPO  default: sergiorivas/psr-banks
#   PSRBANKS_TAP_DIR      local checkout of the tap (default: ../../../homebrew-tap,
#                         i.e. ~/PARA/projects/homebrew-tap)
#
# Usage: Scripts/publish_cask.sh [version]

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${1:-$("$ROOT_DIR/Scripts/version.sh")}"
GITHUB_REPO="${PSRBANKS_GITHUB_REPO:-sergiorivas/psr-banks}"
TAP_DIR="${PSRBANKS_TAP_DIR:-$ROOT_DIR/../../homebrew-tap}"
CASK_PATH="$TAP_DIR/Casks/psr-banks.rb"

APP_BUNDLE="$ROOT_DIR/PSR Banks.app"
DIST_DIR="$ROOT_DIR/dist"
ZIP_PATH="$DIST_DIR/PSRBanks-$VERSION.zip"

[ -d "$TAP_DIR/.git" ] || { echo "PSRBANKS_TAP_DIR ($TAP_DIR) is not a git checkout" >&2; exit 1; }
command -v gh >/dev/null 2>&1 || { echo "Missing 'gh' on PATH" >&2; exit 1; }
[ -z "$(git -C "$ROOT_DIR" status --porcelain)" ] || { echo "Working tree is dirty; commit first" >&2; exit 1; }

echo "==> 1/5 Running tests"
if [[ "$(sysctl -in hw.optional.arm64 2>/dev/null)" == "1" ]] && [[ "$(sysctl -in sysctl.proc_translated 2>/dev/null)" == "1" ]]; then
    (cd "$ROOT_DIR" && arch -arm64 swift test)
else
    (cd "$ROOT_DIR" && swift test)
fi

echo "==> 2/5 Building and packaging ($VERSION)"
PSRBANKS_VERSION="$VERSION" "$ROOT_DIR/Scripts/build_app.sh"
mkdir -p "$DIST_DIR"
rm -f "$ZIP_PATH"
STAGE_DIR="$DIST_DIR/stage"
rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR"
ditto "$APP_BUNDLE" "$STAGE_DIR/PSR Banks.app"
ditto -c -k "$STAGE_DIR" "$ZIP_PATH"
rm -rf "$STAGE_DIR"
SHA256="$(shasum -a 256 "$ZIP_PATH" | awk '{print $1}')"
echo "    sha256 = $SHA256"

echo "==> 3/5 Tagging v$VERSION"
if git -C "$ROOT_DIR" rev-parse -q --verify "refs/tags/v$VERSION" >/dev/null; then
    echo "    v$VERSION already exists locally"
else
    git -C "$ROOT_DIR" tag -a "v$VERSION" -m "PSR Banks $VERSION"
fi
git -C "$ROOT_DIR" push origin HEAD
git -C "$ROOT_DIR" push origin "v$VERSION"

echo "==> 4/5 Publishing the GitHub release"
NOTES="$(awk -v v="## $VERSION" '$0==v{f=1;next} /^## /{f=0} f' "$ROOT_DIR/CHANGELOG.md")"
if gh release view "v$VERSION" --repo "$GITHUB_REPO" >/dev/null 2>&1; then
    gh release upload "v$VERSION" "$ZIP_PATH" --repo "$GITHUB_REPO" --clobber
else
    gh release create "v$VERSION" "$ZIP_PATH" --repo "$GITHUB_REPO" \
        --title "PSR Banks $VERSION" --notes "${NOTES:-See CHANGELOG.md}"
fi

echo "==> 5/5 Updating the tap cask"
mkdir -p "$TAP_DIR/Casks"
cat > "$CASK_PATH" <<RUBY
cask "psr-banks" do
  version "$VERSION"
  sha256 "$SHA256"

  url "https://github.com/$GITHUB_REPO/releases/download/v#{version}/PSRBanks-#{version}.zip"
  name "PSR Banks"
  desc "Library and setlist manager for Yamaha PSR-E483 registration memory files"
  homepage "https://github.com/$GITHUB_REPO"

  depends_on macos: :sonoma

  app "PSR Banks.app"

  postflight_steps do
    # Ad-hoc signed, not notarized: strip the download's quarantine flag.
    run "/usr/bin/xattr", args: ["-cr", "{{appdir}}/PSR Banks.app"]
  end

  caveats do
    <<~EOS
      This build is ad-hoc signed, not notarized by Apple. If macOS still
      refuses to open it, run:
        xattr -cr "#{appdir}/PSR Banks.app"
    EOS
  end
end
RUBY
(
    cd "$TAP_DIR"
    git add Casks/psr-banks.rb
    if git diff --cached --quiet; then
        echo "    No changes to commit in the tap"
    else
        git commit -m "psr-banks $VERSION"
        git push
    fi
)
echo "==> Done. 'brew install --cask sergiorivas/tap/psr-banks' should install $VERSION."
