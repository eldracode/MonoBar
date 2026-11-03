APP := monobar
BINDIR ?= $(HOME)/.local/bin
APP_BUNDLE ?= $(HOME)/Applications/MonoBar.app

.PHONY: build release install install-config

build:
	swift build

release:
	swift build -c release

install: release
	mkdir -p $(BINDIR)
	install -m 755 .build/release/$(APP) $(BINDIR)/$(APP)
	mkdir -p "$(APP_BUNDLE)/Contents/MacOS"
	mkdir -p "$(APP_BUNDLE)/Contents/Resources"
	install -m 755 .build/release/$(APP) "$(APP_BUNDLE)/Contents/MacOS/$(APP)"
	install -m 644 Resources/Info.plist "$(APP_BUNDLE)/Contents/Info.plist"
	printf 'APPL????' > "$(APP_BUNDLE)/Contents/PkgInfo"
	install -m 644 Resources/MonoBar.icns "$(APP_BUNDLE)/Contents/Resources/MonoBar.icns"
	cp -R .build/release/MonoBar_MonoBar.bundle "$(APP_BUNDLE)/Contents/Resources/"
	codesign --force --deep --sign - "$(APP_BUNDLE)"

install-config:
	mkdir -p $(HOME)/.config/monobar
	cp config/config.toml $(HOME)/.config/monobar/config.toml
