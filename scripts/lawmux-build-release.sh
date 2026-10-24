#!/usr/bin/env bash
# Build the Release lawmux.app from this checkout, without Apple Developer
# signing (ad-hoc), and optionally install or open it.
#
#   scripts/lawmux-build-release.sh            build; prints the lawmux.app path
#   scripts/lawmux-build-release.sh --install  also copy it to /Applications/lawmux.app
#   scripts/lawmux-build-release.sh --open     also open the built (or installed) app
#   scripts/lawmux-build-release.sh --install --open --detach
#       build here, then hand the quit / install / relaunch steps to a detached
#       process. Use this when running inside lawmux itself: quitting lawmux
#       would otherwise kill this script (and the agent that ran it) before the
#       install happens. The detached step logs to the DerivedData directory
#       and lawmux's session restore brings the terminal (and a Claude session
#       in it) back after the relaunch.
#
# Why not scripts/reload.sh or scripts/reloadp.sh: upstream's tagged builds force
# a com.cmuxterm.app.debug.<tag> bundle id, and reloadp.sh refuses to run while the
# user's cmux is open. lawmux has its own bundle id (com.lawrenceturnerw.lawmux),
# its own DerivedData and never launches by itself, so it cannot replace a running
# cmux. See LAWMUX.md.
set -euo pipefail

EXPECTED_BUNDLE_ID="com.lawrenceturnerw.lawmux"
DEST="/Applications/lawmux.app"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
INSTALL=0
OPEN=0
DETACH=0
DETACHED_PHASE=0
for arg in "$@"; do
  case "$arg" in
    --install) INSTALL=1 ;;
    --open) OPEN=1 ;;
    --detach) DETACH=1 ;;
    --detached-install-phase) DETACHED_PHASE=1 ;;  # internal: the child started by --detach
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done
if [[ "$DETACH" == 1 && "$INSTALL" != 1 ]]; then
  echo "error: --detach only makes sense together with --install" >&2
  exit 2
fi

cd "$(git rev-parse --show-toplevel)"
# Xcode run-script phases look here for cargo, go, zig and bun. Homebrew's
# rustup is keg-only, so its cargo proxy lives in opt/rustup/bin, not bin.
export PATH="${CARGO_HOME:-${HOME}/.cargo}/bin:/opt/homebrew/opt/rustup/bin:/opt/homebrew/bin:/usr/local/bin:${PATH}"

DERIVED_DATA="${LAWMUX_DERIVED_DATA:-${HOME}/Library/Developer/Xcode/DerivedData/lawmux-release}"
PRODUCTS="$DERIVED_DATA/Build/Products/Release"
APP="$PRODUCTS/lawmux.app"
DETACH_LOG="$DERIVED_DATA/lawmux-install.log"

lawmux_is_running() {
  # pgrep -f occasionally misses a match; ps is reliable for this check.
  # Not `ps | grep -q`: under pipefail, grep -q exiting early kills ps with
  # SIGPIPE and the pipeline reports failure even on a match.
  [[ -n "$(ps -axo comm= | grep -F "$DEST/Contents/MacOS/cmux" || true)" ]]
}

verify_app() {
  # The bundle's directory name is not part of the code signature, but verify anyway.
  codesign --verify --deep --strict "$APP"
  BUNDLE_ID="$(defaults read "$APP/Contents/Info.plist" CFBundleIdentifier)"
  if [[ "$BUNDLE_ID" != "$EXPECTED_BUNDLE_ID" ]]; then
    echo "error: built app has bundle id '$BUNDLE_ID', expected '$EXPECTED_BUNDLE_ID'" >&2
    echo "error: refusing to continue; it could collide with the installed cmux" >&2
    exit 1
  fi
}

# Refuses to touch /Applications/lawmux.app unless it is lawmux. Never touches
# /Applications/cmux.app.
check_install_target() {
  if [[ -e "$DEST" ]]; then
    EXISTING_ID="$(defaults read "$DEST/Contents/Info.plist" CFBundleIdentifier 2>/dev/null || true)"
    if [[ "$EXISTING_ID" != "$EXPECTED_BUNDLE_ID" ]]; then
      echo "error: $DEST exists but is not lawmux (bundle id '$EXISTING_ID'); not replacing it" >&2
      exit 1
    fi
  fi
}

install_app() {
  echo "==> Installing to $DEST"
  rm -rf "$DEST"
  ditto "$APP" "$DEST"
  # Launch Services otherwise remembers the build copy too and may open it for
  # the bundle id; the installed app is the only one that should be registered.
  "$LSREGISTER" -u "$APP" >/dev/null 2>&1 || true
  "$LSREGISTER" -f "$DEST" >/dev/null 2>&1 || true
}

print_result() {
  echo
  echo "lawmux.app: $1"
  echo "bundle id:  $BUNDLE_ID ($(codesign -dv "$1" 2>&1 | sed -n 's/^Signature=//p'))"
}

# ---------------------------------------------------------------------------
# Detached phase: quit lawmux, install, relaunch. Runs as the nohup child that
# --detach starts after the build; everything below is logged to $DETACH_LOG.
# ---------------------------------------------------------------------------
if [[ "$DETACHED_PHASE" == 1 ]]; then
  echo "==> [$(date '+%H:%M:%S')] detached install phase started (pid $$)"
  verify_app
  check_install_target
  if lawmux_is_running; then
    echo "==> Asking lawmux to quit"
    osascript -e "tell application id \"$EXPECTED_BUNDLE_ID\" to quit" || true
    for _ in $(seq 1 60); do
      lawmux_is_running || break
      sleep 0.5
    done
    if lawmux_is_running; then
      echo "error: lawmux is still running after 30s; not installing" >&2
      exit 1
    fi
    # Let the app finish writing its session snapshot after the process exits.
    sleep 1
  fi
  install_app
  if [[ "$OPEN" == 1 ]]; then
    echo "==> Relaunching lawmux"
    open "$DEST"
  fi
  print_result "$DEST"
  echo "==> [$(date '+%H:%M:%S')] done"
  exit 0
fi

# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------
for tool in xcodebuild cargo go zig bun; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "error: $tool not found on PATH; see LAWMUX.md for the prerequisites" >&2
    exit 1
  fi
done
if [[ ! -e GhosttyKit.xcframework ]]; then
  echo "error: GhosttyKit.xcframework is missing; run ./scripts/setup.sh first" >&2
  exit 1
fi

# Keep Spotlight (and so Launchpad) from listing the build output as a second
# lawmux next to /Applications/lawmux.app.
mkdir -p "$DERIVED_DATA"
touch "$DERIVED_DATA/.metadata_never_index"

# Build settings lawmux overrides on the command line (upstream's project stays
# untouched). Changing either knob invalidates the Swift build cache, so the
# first build after a switch is a full one.
#
#   LAWMUX_UNIVERSAL=1  also build x86_64 (default: the current arch only;
#                       the Rust/Go sidecars read ARCHS as well)
#   LAWMUX_WMO=1        whole-module optimization like upstream's release
#                       (default: incremental, so small edits rebuild fast)
BUILD_SETTINGS=(
  CODE_SIGN_ENTITLEMENTS=
  CMUX_CUA_HELPER_DISPLAY_NAME="lawmux Computer Use"
)
if [[ "${LAWMUX_UNIVERSAL:-0}" == 1 ]]; then
  ARCH_NOTE="universal (arm64 + x86_64)"
else
  BUILD_SETTINGS+=(ARCHS="$(uname -m)" ONLY_ACTIVE_ARCH=YES)
  ARCH_NOTE="$(uname -m) only"
fi
if [[ "${LAWMUX_WMO:-0}" == 1 ]]; then
  MODE_NOTE="whole-module"
else
  BUILD_SETTINGS+=(SWIFT_COMPILATION_MODE=incremental)
  MODE_NOTE="incremental"
fi

echo "==> Building Release into $DERIVED_DATA ($ARCH_NOTE, $MODE_NOTE Swift compilation)"
# CODE_SIGN_ENTITLEMENTS= mirrors upstream's Release dev builds: the entitlements
# file needs a provisioning profile that an ad-hoc build does not have.
xcodebuild \
  -project cmux.xcodeproj \
  -scheme cmux \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA" \
  "${BUILD_SETTINGS[@]}" \
  build

echo "==> Renaming cmux.app to lawmux.app"
rm -rf "$APP"
mv "$PRODUCTS/cmux.app" "$APP"
verify_app

# ---------------------------------------------------------------------------
# Install / open
# ---------------------------------------------------------------------------
if [[ "$INSTALL" == 1 && "$DETACH" == 1 ]]; then
  check_install_target
  echo "==> Handing quit / install / relaunch to a detached process"
  echo "    log: $DETACH_LOG"
  phase_args=(--install --detached-install-phase)
  [[ "$OPEN" == 1 ]] && phase_args+=(--open)
  # nohup + a fresh stdin/stdout so the child outlives this terminal when
  # lawmux quits; LAWMUX_DERIVED_DATA keeps it on the same build output.
  LAWMUX_DERIVED_DATA="$DERIVED_DATA" nohup bash "$0" "${phase_args[@]}" \
    </dev/null >"$DETACH_LOG" 2>&1 &
  disown
  print_result "$APP"
  echo
  echo "lawmux will quit in a moment; the detached process installs and relaunches it."
  exit 0
fi

TARGET="$APP"
if [[ "$INSTALL" == 1 ]]; then
  check_install_target
  if lawmux_is_running; then
    echo "error: $DEST is running; quit lawmux first, rerun with --install, or use --detach" >&2
    exit 1
  fi
  install_app
  TARGET="$DEST"
fi

if [[ "$OPEN" == 1 ]]; then
  open "$TARGET"
fi

print_result "$TARGET"
