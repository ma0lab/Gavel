APP     = ClaudeBar.app
DIST    = dist/$(APP)
DEST    = /Applications/$(APP)
VERSION = $(shell /usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist 2>/dev/null || echo "1.0")
DMG     = dist/ClaudeBar-$(VERSION).dmg

.PHONY: build deploy run clean dmg

build:
	bash scripts/build.sh

deploy: build
	pkill -f "$(APP)/Contents/MacOS" 2>/dev/null || true
	rm -rf "$(DEST)"
	cp -R "$(DIST)" /Applications/
	open "$(DEST)"

run:
	pkill -f "$(APP)/Contents/MacOS" 2>/dev/null || true
	open "$(DIST)"

clean:
	rm -rf dist .build

dmg: build
	rm -f "$(DMG)"
	hdiutil create \
		-volname "ClaudeBar" \
		-srcfolder "$(DIST)" \
		-ov \
		-format UDZO \
		"$(DMG)"
	@echo "Created: $(DMG)"
