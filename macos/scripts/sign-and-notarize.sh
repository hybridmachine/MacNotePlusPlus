#!/usr/bin/env bash
#
# sign-and-notarize.sh -- Sign and notarize PaperWasp.app and produce a signed DMG
#
# This script performs inside-out signing: every nested Mach-O (plugin dylibs,
# frameworks) is signed before the outer bundle, then a fresh DMG is built from
# the signed .app and signed itself. The DMG is submitted to Apple for
# notarization and the ticket is stapled to both the DMG and the .app.
#
# Usage:
#   ./sign-and-notarize.sh [options]
#
# Required environment variables:
#   CODESIGN_IDENTITY    - Signing identity (e.g., "Developer ID Application: Name (TEAMID)")
#
# For notarization (skip with --skip-notarize):
#   Password auth:  APPLE_ID + APPLE_TEAM_ID + APPLE_APP_PASSWORD
#   API key auth:   APPLE_API_KEY + APPLE_API_ISSUER (+ optional APPLE_API_KEY_PATH)
#
# Options:
#   --app-path PATH      Path to .app bundle (default: macos/dist/PaperWasp.app)
#   --dmg-output PATH    Output path for signed DMG (default: macos/dist/PaperWasp.dmg)
#   --volname NAME       DMG volume name (default: PaperWasp)
#   --entitlements PATH  Path to entitlements (default: macos/platform/PaperWasp.entitlements)
#   --skip-notarize      Only sign, do not submit for notarization
#   --skip-dmg           Only sign/notarize the .app (no DMG produced)
#   --verbose            Enable verbose output
#   --help               Show this help

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
MACOS_DIR="$REPO_ROOT/macos"

# Defaults
APP_PATH="${MACOS_DIR}/dist/PaperWasp.app"
DMG_OUTPUT="${MACOS_DIR}/dist/PaperWasp.dmg"
DMG_VOLNAME="PaperWasp"
ENTITLEMENTS="${MACOS_DIR}/platform/PaperWasp.entitlements"
SKIP_NOTARIZE=false
SKIP_DMG=false
VERBOSE=false

require_arg() {
	if [[ $# -lt 2 || "$2" == --* ]]; then
		echo "ERROR: $1 requires a value" >&2; exit 1
	fi
}

while [[ $# -gt 0 ]]; do
	case "$1" in
		--app-path)      require_arg "$1" "${2:-}"; APP_PATH="$2"; shift 2 ;;
		--dmg-output)    require_arg "$1" "${2:-}"; DMG_OUTPUT="$2"; shift 2 ;;
		--volname)       require_arg "$1" "${2:-}"; DMG_VOLNAME="$2"; shift 2 ;;
		--entitlements)  require_arg "$1" "${2:-}"; ENTITLEMENTS="$2"; shift 2 ;;
		--skip-notarize) SKIP_NOTARIZE=true; shift ;;
		--skip-dmg)      SKIP_DMG=true; shift ;;
		--verbose)       VERBOSE=true; shift ;;
		--help)          sed -n '2,28p' "$0"; exit 0 ;;
		*)               echo "Unknown option: $1" >&2; exit 1 ;;
	esac
done

log()     { echo "==> $*"; }
warn()    { echo "WARNING: $*" >&2; }
die()     { echo "ERROR: $*" >&2; exit 1; }
verbose() { $VERBOSE && echo "    $*" || true; }

# --- Validation --------------------------------------------------------

[[ -z "${CODESIGN_IDENTITY:-}" ]] && die "CODESIGN_IDENTITY is not set"
[[ -d "$APP_PATH" ]] || die "App bundle not found: $APP_PATH"
[[ -f "$ENTITLEMENTS" ]] || die "Entitlements not found: $ENTITLEMENTS"

AUTH_MODE=""
NOTARY_AUTH_FLAGS=()
if ! $SKIP_NOTARIZE; then
	if [[ -n "${APPLE_API_KEY:-}" ]]; then
		[[ -n "${APPLE_API_ISSUER:-}" ]] || die "APPLE_API_ISSUER required with APPLE_API_KEY"
		AUTH_MODE="apikey"
		key_path="${APPLE_API_KEY_PATH:-$HOME/.private_keys/AuthKey_${APPLE_API_KEY}.p8}"
		NOTARY_AUTH_FLAGS=(--key "$key_path" --key-id "$APPLE_API_KEY" --issuer "$APPLE_API_ISSUER")
	elif [[ -n "${APPLE_ID:-}" ]]; then
		[[ -n "${APPLE_TEAM_ID:-}" ]]      || die "APPLE_TEAM_ID required with APPLE_ID"
		[[ -n "${APPLE_APP_PASSWORD:-}" ]] || die "APPLE_APP_PASSWORD required with APPLE_ID"
		AUTH_MODE="password"
		NOTARY_AUTH_FLAGS=(--apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" --password "$APPLE_APP_PASSWORD")
	else
		die "Set APPLE_API_KEY+APPLE_API_ISSUER or APPLE_ID+APPLE_TEAM_ID+APPLE_APP_PASSWORD for notarization"
	fi
fi

# --- Step 1: Sign the .app bundle (inside-out) -------------------------

log "Signing app bundle: $APP_PATH"
verbose "Identity: $CODESIGN_IDENTITY"
verbose "Entitlements: $ENTITLEMENTS"

# Strip extended attributes (resource forks, Finder info) that block codesign
xattr -cr "$APP_PATH"

# Sign every nested Mach-O first (plugin dylibs, helpers, frameworks) with the
# hardened runtime and a secure timestamp. Apple notarization rejects bundles
# whose nested binaries lack either. We sign the nested items before the outer
# bundle so the outer seal covers valid signatures.
NESTED_BINARIES=()
while IFS= read -r -d '' f; do
	NESTED_BINARIES+=("$f")
done < <(find "$APP_PATH/Contents" \
	\( -path "$APP_PATH/Contents/MacOS/*" -prune \) -o \
	\( -name "*.dylib" -o -name "*.framework" -o -name "*.bundle" \) -print0)

for nested in "${NESTED_BINARIES[@]}"; do
	log "Signing nested: ${nested#$APP_PATH/}"
	codesign --force --options runtime \
		--sign "$CODESIGN_IDENTITY" \
		--timestamp \
		"$nested"
done

# --deep re-signs every Mach-O the bundle contains, which is defensive — the
# explicit nested pass above already covered the plugins, so this is mostly a
# belt-and-suspenders pass that also seals non-Mach-O resources (e.g. images
# dropped in Contents/MacOS/) that plain codesign would otherwise reject.
codesign --force --options runtime \
	--sign "$CODESIGN_IDENTITY" \
	--entitlements "$ENTITLEMENTS" \
	--timestamp \
	--deep \
	"$APP_PATH"

log "Verifying app signature..."
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

log "Checking Gatekeeper acceptance (pre-notarization)..."
spctl --assess --type execute --verbose=2 "$APP_PATH" 2>&1 || \
	warn "App does not yet pass Gatekeeper (expected before notarization)"

# --- Step 2: Build a fresh DMG from the signed .app --------------------

DMG_PATH=""
if ! $SKIP_DMG; then
	STAGE_ROOT="$(mktemp -d -t paperwasp-sign)"
	STAGE_DMG_ROOT="$STAGE_ROOT/dmg-root"
	trap 'rm -rf "$STAGE_ROOT"' EXIT

	mkdir -p "$STAGE_DMG_ROOT"
	log "Staging signed .app in $STAGE_DMG_ROOT"
	ditto "$APP_PATH" "$STAGE_DMG_ROOT/$(basename "$APP_PATH")"
	ln -sf /Applications "$STAGE_DMG_ROOT/Applications"

	# Build into the staging dir, not into dist/, to avoid xattrs reappearing
	# during creation on iCloud-synced volumes. Copy the final artifact at the
	# end.
	STAGE_DMG="$STAGE_ROOT/$(basename "$DMG_OUTPUT")"
	log "Creating DMG: $STAGE_DMG"
	hdiutil create \
		-volname "$DMG_VOLNAME" \
		-srcfolder "$STAGE_DMG_ROOT" \
		-format UDZO \
		-ov \
		"$STAGE_DMG" >/dev/null

	log "Signing DMG"
	codesign --force --sign "$CODESIGN_IDENTITY" --timestamp "$STAGE_DMG"
	codesign --verify --verbose=2 "$STAGE_DMG"

	mkdir -p "$(dirname "$DMG_OUTPUT")"
	cp "$STAGE_DMG" "$DMG_OUTPUT"
	DMG_PATH="$DMG_OUTPUT"
fi

# --- Step 3: Notarize --------------------------------------------------

if ! $SKIP_NOTARIZE; then
	if ! $SKIP_DMG && [[ -f "$DMG_PATH" ]]; then
		NOTARIZE_TARGET="$DMG_PATH"
		CLEANUP_NOTARIZE_TARGET=false
	else
		NOTARIZE_TARGET="$(mktemp -t paperwasp-notarize).zip"
		log "Creating zip for notarization: $NOTARIZE_TARGET"
		ditto -c -k --keepParent "$APP_PATH" "$NOTARIZE_TARGET"
		CLEANUP_NOTARIZE_TARGET=true
	fi

	log "Submitting for notarization: $NOTARIZE_TARGET"
	verbose "This typically takes 1-5 minutes."

	xcrun notarytool submit "$NOTARIZE_TARGET" \
		"${NOTARY_AUTH_FLAGS[@]}" \
		--wait \
		--timeout 30m

	# --- Step 4: Staple ------------------------------------------------

	if ! $SKIP_DMG && [[ -f "$DMG_PATH" ]]; then
		log "Stapling notarization ticket to DMG: $DMG_PATH"
		xcrun stapler staple "$DMG_PATH"
	fi

	log "Stapling notarization ticket to app: $APP_PATH"
	xcrun stapler staple "$APP_PATH"

	if $CLEANUP_NOTARIZE_TARGET; then
		rm -f "$NOTARIZE_TARGET"
	fi
fi

# --- Final verification -------------------------------------------------

log "Final verification..."
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

if ! $SKIP_NOTARIZE; then
	spctl --assess --type execute --verbose=2 "$APP_PATH" || true
	if ! $SKIP_DMG && [[ -f "$DMG_PATH" ]]; then
		spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG_PATH" || true
	fi
fi

log "Done. Artifacts:"
log "  App: $APP_PATH"
if ! $SKIP_DMG && [[ -n "$DMG_PATH" ]]; then
	log "  DMG: $DMG_PATH"
fi
