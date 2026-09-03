.PHONY: release clean release-zip release-dmg

release:
	xcodebuild -project StillMotion.xcodeproj -scheme StillMotion -configuration Release \
		-derivedDataPath .build/DerivedData build

release-zip: release
	@set -e; \
	APP=".build/DerivedData/Build/Products/Release/StillMotion.app"; \
	test -d "$$APP"; \
	VERSION=$$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$$APP/Contents/Info.plist"); \
	test -z "$$(git status --porcelain --untracked-files=normal)" || VERSION="$$VERSION-dirty"; \
	APP_NAME=$$(basename "$$APP" .app); \
	ZIP="$(CURDIR)/$$APP_NAME-$$VERSION.zip"; \
	STAGING=$$(mktemp -d "$${TMPDIR:-/tmp}/stillmotion-zip.XXXXXX"); \
	trap 'rm -rf "$$STAGING"' EXIT; \
	ditto "$$APP" "$$STAGING/StillMotion.app"; \
	ditto "LICENSE" "$$STAGING/LICENSE"; \
	rm -f "$$ZIP"; \
	ditto -c -k --sequesterRsrc "$$STAGING" "$$ZIP"; \
	echo "Created $$APP_NAME-$$VERSION.zip"; \
	echo "To upload to GitHub:"; \
	echo "  gh release create 'v$$VERSION' $$APP_NAME-$$VERSION.zip --title 'v$$VERSION' --generate-notes"

release-dmg: release
	@set -e; \
	APP=".build/DerivedData/Build/Products/Release/StillMotion.app"; \
	test -d "$$APP"; \
	VERSION=$$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$$APP/Contents/Info.plist"); \
	test -z "$$(git status --porcelain --untracked-files=normal)" || VERSION="$$VERSION-dirty"; \
	DMG="StillMotion-$$VERSION.dmg"; \
	STAGING=$$(mktemp -d "$${TMPDIR:-/tmp}/stillmotion-dmg.XXXXXX"); \
	trap 'rm -rf "$$STAGING"' EXIT; \
	ditto "$$APP" "$$STAGING/StillMotion.app"; \
	ditto "LICENSE" "$$STAGING/LICENSE"; \
	ln -s /Applications "$$STAGING/Applications"; \
	rm -f "$$DMG"; \
	hdiutil create -volname "StillMotion" -srcfolder "$$STAGING" -ov -format UDZO "$$DMG" >/dev/null; \
	hdiutil verify "$$DMG" >/dev/null; \
	echo "Created $$DMG"; \
	echo "This DMG is unsigned; users may need to right-click StillMotion and choose Open."

clean:
	rm -rf .build/DerivedData
	rm -f StillMotion*.app StillMotion*.app.dSYM *.zip *.dmg
