#!/bin/bash
# Installs a "Compress with Darkroom" Finder Quick Action (right-click → Quick Actions).
# Works on images and folders. Requires Beachman Darkroom to be installed first.
set -euo pipefail

NAME="Compress with Darkroom"
WF="$HOME/Library/Services/$NAME.workflow"

echo "Installing Quick Action: $NAME"
rm -rf "$WF"
mkdir -p "$WF/Contents"

# --- The real work lives in its own executable script inside the bundle. -------
# The Automator action just calls it, so nothing has to survive plist escaping.
cat > "$WF/Contents/compress.sh" <<'SCRIPT_EOF'
#!/bin/bash
export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$PATH"

notify() {
  osascript - "$1" <<'AS' 2>/dev/null
on run argv
  display notification (item 1 of argv) with title "Beachman Darkroom"
end run
AS
}

alert() {
  osascript - "$1" <<'AS' 2>/dev/null
on run argv
  display alert "Beachman Darkroom" message (item 1 of argv)
end run
AS
}

DR=""
for c in "/Applications/Beachman Darkroom.app/Contents/MacOS/BeachmanDarkroom" \
         "$HOME/Applications/Beachman Darkroom.app/Contents/MacOS/BeachmanDarkroom" \
         "$(command -v darkroom 2>/dev/null || true)"; do
  if [ -n "$c" ] && [ -x "$c" ]; then DR="$c"; break; fi
done

if [ -z "$DR" ]; then
  alert "Beachman Darkroom isn't installed. Install the app, then try again."
  exit 1
fi

[ "$#" -eq 0 ] && exit 0

OUT=$("$DR" optimize --quality 80 "$@" 2>&1) || true
SUMMARY=$(printf '%s\n' "$OUT" | grep '^TOTAL' | head -1)
[ -z "$SUMMARY" ] && SUMMARY=$(printf '%s\n' "$OUT" | tail -1)
[ -z "$SUMMARY" ] && SUMMARY="Nothing to compress."

notify "${SUMMARY#TOTAL } → Documents/Beachman Darkroom/Optimizer"
SCRIPT_EOF
chmod +x "$WF/Contents/compress.sh"

# --- Service registration ------------------------------------------------------
cat > "$WF/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>NSServices</key>
	<array>
		<dict>
			<key>NSMenuItem</key>
			<dict>
				<key>default</key>
				<string>Compress with Darkroom</string>
			</dict>
			<key>NSMessage</key>
			<string>runWorkflowAsService</string>
			<key>NSRequiredContext</key>
			<dict>
				<key>NSApplicationIdentifier</key>
				<string>com.apple.finder</string>
			</dict>
			<key>NSSendFileTypes</key>
			<array>
				<string>public.image</string>
				<string>public.folder</string>
			</array>
		</dict>
	</array>
</dict>
</plist>
PLIST

# --- Automator workflow --------------------------------------------------------
cat > "$WF/Contents/document.wflow" <<'WFLOW'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>AMApplicationBuild</key><string>521</string>
	<key>AMApplicationVersion</key><string>2.10</string>
	<key>AMDocumentVersion</key><string>2</string>
	<key>actions</key>
	<array>
		<dict>
			<key>action</key>
			<dict>
				<key>AMAccepts</key>
				<dict>
					<key>Container</key><string>List</string>
					<key>Optional</key><true/>
					<key>Types</key><array><string>com.apple.cocoa.string</string></array>
				</dict>
				<key>AMActionVersion</key><string>2.0.3</string>
				<key>AMProvides</key>
				<dict>
					<key>Container</key><string>List</string>
					<key>Types</key><array><string>com.apple.cocoa.string</string></array>
				</dict>
				<key>ActionBundlePath</key>
				<string>/System/Library/Automator/Run Shell Script.action</string>
				<key>ActionName</key><string>Run Shell Script</string>
				<key>ActionParameters</key>
				<dict>
					<key>COMMAND_STRING</key>
					<string>exec "$HOME/Library/Services/Compress with Darkroom.workflow/Contents/compress.sh" "$@"</string>
					<key>CheckedForUserDefaultShell</key><true/>
					<key>inputMethod</key><integer>1</integer>
					<key>shell</key><string>/bin/bash</string>
					<key>source</key><string></string>
				</dict>
				<key>BundleIdentifier</key><string>com.apple.RunShellScript</string>
				<key>CFBundleVersion</key><string>2.0.3</string>
				<key>CanShowSelectedItemsWhenRun</key><false/>
				<key>CanShowWhenRun</key><true/>
				<key>Category</key><array><string>AMCategoryUtilities</string></array>
				<key>Class Name</key><string>RunShellScriptAction</string>
				<key>InputUUID</key><string>7B7C1F00-0001-4000-8000-000000000001</string>
				<key>Keywords</key><array><string>Shell</string><string>Script</string></array>
				<key>OutputUUID</key><string>7B7C1F00-0002-4000-8000-000000000002</string>
				<key>UUID</key><string>7B7C1F00-0003-4000-8000-000000000003</string>
				<key>ShowWhenRun</key><false/>
			</dict>
			<key>isViewVisible</key><integer>1</integer>
		</dict>
	</array>
	<key>connectors</key><dict/>
	<key>workflowMetaData</key>
	<dict>
		<key>serviceApplicationBundleID</key><string>com.apple.finder</string>
		<key>serviceApplicationPath</key><string>/System/Library/CoreServices/Finder.app</string>
		<key>serviceInputTypeIdentifier</key><string>com.apple.Automator.fileSystemObject.image</string>
		<key>serviceOutputTypeIdentifier</key><string>com.apple.Automator.nothing</string>
		<key>serviceProcessesInput</key><integer>0</integer>
		<key>workflowTypeIdentifier</key><string>com.apple.Automator.servicesMenu</string>
	</dict>
</dict>
</plist>
WFLOW

plutil -lint "$WF/Contents/document.wflow" >/dev/null
plutil -lint "$WF/Contents/Info.plist" >/dev/null
bash -n "$WF/Contents/compress.sh"

/System/Library/CoreServices/pbs -update 2>/dev/null || true

echo
echo "Installed: $WF"
echo "Right-click any image or folder in Finder → Quick Actions → Compress with Darkroom"
echo "(If it doesn't appear, enable it in System Settings → General → Login Items & Extensions → Finder.)"
