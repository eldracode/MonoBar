APP := polybar-mac
BINDIR ?= $(HOME)/.local/bin
APP_BUNDLE ?= $(HOME)/Applications/PolybarMac.app

.PHONY: build release install install-config

build:
	swift build

release:
	swift build -c release

install: release
	mkdir -p $(BINDIR)
	install -m 755 .build/release/$(APP) $(BINDIR)/$(APP)
	mkdir -p "$(APP_BUNDLE)/Contents/MacOS"
	install -m 755 .build/release/$(APP) "$(APP_BUNDLE)/Contents/MacOS/$(APP)"
	install -m 644 Resources/Info.plist "$(APP_BUNDLE)/Contents/Info.plist"
	codesign --force --deep --sign - "$(APP_BUNDLE)"

install-config:
	mkdir -p $(HOME)/.config/polybar-mac
	cp config/config.toml $(HOME)/.config/polybar-mac/config.toml
