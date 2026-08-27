.PHONY: release clean release-zip

release:
	xcodebuild -project StillMotion.xcodeproj -scheme StillMotion -configuration Release \
		-derivedDataPath .build/DerivedData build

release-zip: release
	@set -e; \
	APP="$(shell find .build/DerivedData/Build/Products/Release -name '*.app' | head -1)"; \
	VERSION=$$(git describe --tags --always | sed 's/^v//'); \
	APP_NAME=$$(basename "$$APP" .app); \
	ditto -c -k --keepParent "$$APP" "$$APP_NAME-$$VERSION.zip"; \
	echo "Created $$APP_NAME-$$VERSION.zip"; \
	echo "To upload to GitHub:"; \
	echo "  gh release create '$$VERSION' $$APP_NAME-$$VERSION.zip --title '$$VERSION' --generate-notes"

clean:
	rm -rf .build/DerivedData
	rm -f StillMotion*.app StillMotion*.app.dSYM *.zip
