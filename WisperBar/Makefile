# WisperBar – Build-Hilfsskript
# Verwendung: make build | make run | make open | make clean

SCHEME      = WisperBar
CONFIG      = Debug
BUILD_DIR   = .build
APP_PATH    = $(BUILD_DIR)/Build/Products/$(CONFIG)/$(SCHEME).app

.PHONY: build run open clean regen

## Projekt neu generieren (nach Änderungen an project.yml)
regen:
	xcodegen generate

## App bauen (Debug, ohne Code-Signing)
build: regen
	xcodebuild -scheme $(SCHEME) -configuration $(CONFIG) \
	  -derivedDataPath $(BUILD_DIR) \
	  CODE_SIGN_IDENTITY="-" \
	  CODE_SIGNING_REQUIRED=NO \
	  CODE_SIGNING_ALLOWED=NO \
	  build | xcpretty || xcodebuild -scheme $(SCHEME) -configuration $(CONFIG) \
	  -derivedDataPath $(BUILD_DIR) \
	  CODE_SIGN_IDENTITY="-" \
	  CODE_SIGNING_REQUIRED=NO \
	  CODE_SIGNING_ALLOWED=NO \
	  build 2>&1 | grep -E "error:|warning:|BUILD"

## App starten
run: build
	open "$(APP_PATH)"

## Bereits gebaute App öffnen
open:
	open "$(APP_PATH)"

## Alle Build-Artefakte löschen
clean:
	rm -rf $(BUILD_DIR)
	@echo "Clean abgeschlossen."
