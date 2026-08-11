#!/bin/bash
# Builds Beachman Darkroom.app — self-contained, offline, ad-hoc signed.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PKG="$ROOT/packaging"
APP="$ROOT/dist/Beachman Darkroom.app"
BIN="$APP/Contents/Resources/bin"
LIB="$APP/Contents/Resources/lib"

echo "==> Building Swift executable"
cd "$ROOT"
swift build -c release

echo "==> Assembling bundle"
rm -rf "$ROOT/dist"
mkdir -p "$APP/Contents/MacOS" "$BIN" "$LIB"
cp "$ROOT/.build/release/BeachmanDarkroom" "$APP/Contents/MacOS/"
cp "$PKG/Info.plist" "$APP/Contents/"
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "==> Icon"
ICONDIR="$ROOT/dist/AppIcon.iconset"
mkdir -p "$ICONDIR"
swift "$PKG/GenIcon.swift" "$ROOT/dist/icon_1024.png" >/dev/null
for sz in 16 32 64 128 256 512; do
  sips -z $sz $sz       "$ROOT/dist/icon_1024.png" --out "$ICONDIR/icon_${sz}x${sz}.png"      >/dev/null
  sips -z $((sz*2)) $((sz*2)) "$ROOT/dist/icon_1024.png" --out "$ICONDIR/icon_${sz}x${sz}@2x.png" >/dev/null
done
cp "$ROOT/dist/icon_1024.png" "$ICONDIR/icon_512x512@2x.png"
iconutil -c icns "$ICONDIR" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONDIR" "$ROOT/dist/icon_1024.png"

echo "==> Bundling engines"
TOOLS=(
  /opt/homebrew/bin/pngquant
  /opt/homebrew/bin/oxipng
  /opt/homebrew/bin/cwebp
  /opt/homebrew/bin/dwebp
  /opt/homebrew/bin/gifsicle
  /opt/homebrew/opt/mozjpeg/bin/cjpeg
  /opt/homebrew/opt/mozjpeg/bin/djpeg
  /opt/homebrew/opt/mozjpeg/bin/jpegtran
)
for t in "${TOOLS[@]}"; do
  [ -f "$t" ] || { echo "MISSING TOOL: $t"; exit 1; }
  cp -f "$t" "$BIN/$(basename "$t")"
  chmod +w "$BIN/$(basename "$t")"
done

# Copy the transitive dylib closure into Resources/lib and rewrite load paths.
echo "==> Bundling dylib closure"
# Strategy: every non-system dep becomes @rpath/<name>, and each Mach-O gets an
# rpath pointing into Resources/lib. No path-length or duplicate-entry surprises.
resolve_dep() {
  local dep="$1" name
  name=$(basename "$dep")
  if [[ "$dep" == @rpath/* ]]; then
    { ls /opt/homebrew/lib/"$name" /opt/homebrew/opt/*/lib/"$name" 2>/dev/null || true; } | head -1
  else
    echo "$dep"
  fi
}

collect() {  # copy the transitive closure of brew dylibs into $LIB
  local file="$1"
  local deps dep name src
  deps=$(otool -L "$file" | awk 'NR>1{print $1}' | grep -E '^(/opt/homebrew|/usr/local|@rpath)' || true)
  for dep in $deps; do
    name=$(basename "$dep")
    [ "$name" = "$(basename "$file")" ] && continue   # skip self/ID line
    if [ ! -f "$LIB/$name" ]; then
      src=$(resolve_dep "$dep")
      if [ -z "$src" ] || [ ! -f "$src" ]; then
        echo "  !! cannot resolve $dep (needed by $(basename "$file"))"; continue
      fi
      cp -f "$src" "$LIB/$name"
      chmod +w "$LIB/$name"
      collect "$LIB/$name"
    fi
  done
}

rewrite() {  # point all non-system deps at @rpath and add the bundle rpath
  local file="$1" rpath="$2"
  local deps dep name
  deps=$(otool -L "$file" | awk 'NR>1{print $1}' | grep -E '^(/opt/homebrew|/usr/local)' || true)
  for dep in $deps; do
    name=$(basename "$dep")
    if [ "$name" = "$(basename "$file")" ]; then
      install_name_tool -id "@rpath/$name" "$file"
    else
      install_name_tool -change "$dep" "@rpath/$name" "$file"
    fi
  done
  install_name_tool -add_rpath "$rpath" "$file" 2>/dev/null || true
}

for t in "$BIN"/*; do collect "$t"; done
for t in "$BIN"/*; do rewrite "$t" "@loader_path/../lib"; done
for l in "$LIB"/*.dylib; do [ -f "$l" ] && rewrite "$l" "@loader_path"; done

echo "==> Signing (ad-hoc)"
for l in "$LIB"/*.dylib; do [ -f "$l" ] && codesign --force -s - "$l"; done
for t in "$BIN"/*;       do codesign --force -s - "$t"; done
codesign --force -s - "$APP/Contents/MacOS/BeachmanDarkroom"
codesign --force -s - "$APP"

echo "==> Verifying engines run from inside the bundle"
"$BIN/pngquant" --version
"$BIN/cjpeg" -version 2>&1 | head -1
"$BIN/oxipng" --version
"$BIN/cwebp" -version
"$BIN/gifsicle" --version | head -1

echo "==> Writing 'darkroom' PATH shim + installer"
cat > "$ROOT/dist/darkroom" <<'SHIM'
#!/bin/bash
# Beachman Darkroom CLI shim. Finds the app wherever it's installed.
for candidate in \
  "/Applications/Beachman Darkroom.app" \
  "$HOME/Applications/Beachman Darkroom.app" \
  "$(dirname "${BASH_SOURCE[0]}")/Beachman Darkroom.app"
do
  if [ -x "$candidate/Contents/MacOS/BeachmanDarkroom" ]; then
    exec "$candidate/Contents/MacOS/BeachmanDarkroom" "$@"
  fi
done
echo "error: Beachman Darkroom.app not found in /Applications or ~/Applications" >&2
exit 127
SHIM
chmod +x "$ROOT/dist/darkroom"

cat > "$ROOT/dist/Install.command" <<'INSTALL'
#!/bin/bash
# Double-click to install Beachman Darkroom.
set -euo pipefail
cd "$(dirname "$0")"
echo "Installing Beachman Darkroom…"
rm -rf "/Applications/Beachman Darkroom.app"
cp -R "Beachman Darkroom.app" /Applications/
xattr -dr com.apple.quarantine "/Applications/Beachman Darkroom.app" 2>/dev/null || true
for d in /opt/homebrew/bin /usr/local/bin "$HOME/.local/bin"; do
  if [ -d "$d" ] && [ -w "$d" ]; then
    cp -f darkroom "$d/darkroom"; chmod +x "$d/darkroom"
    echo "  CLI installed: $d/darkroom"; break
  fi
done
if [ -f install-quick-action.sh ]; then
  bash install-quick-action.sh >/dev/null 2>&1 && \
    echo "  Finder right-click menu installed" || \
    echo "  (skipped Finder menu)"
fi
echo
echo "Done. Beachman Darkroom is in your Applications folder."
echo
echo "  Finder:   right-click images or a folder -> Quick Actions -> Compress with Darkroom"
echo "  Terminal: darkroom optimize ~/Desktop/photos"
echo "  Claude:   ask it to compress your images (see the repo for the skill)"
echo
read -n 1 -s -r -p "Press any key to close."
INSTALL
chmod +x "$ROOT/dist/Install.command"
cp -f "$PKG/install-quick-action.sh" "$ROOT/dist/install-quick-action.sh"

echo "==> Zipping for distribution"
cd "$ROOT/dist"
ditto -c -k --keepParent "Beachman Darkroom.app" "Beachman-Darkroom.zip"
rm -f "Beachman Darkroom - Install.zip"
mkdir -p .stage && cp -R "Beachman Darkroom.app" darkroom Install.command install-quick-action.sh .stage/
ditto -c -k --sequesterRsrc .stage "Beachman Darkroom - Install.zip"
rm -rf .stage

echo
echo "DONE: $APP"
du -sh "$APP" "$ROOT/dist/Beachman-Darkroom.zip"
