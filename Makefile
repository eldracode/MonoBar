APP := polybar-mac
BINDIR ?= $(HOME)/.local/bin

.PHONY: build release install install-config

build:
	swift build

release:
	swift build -c release

install: release
	mkdir -p $(BINDIR)
	install -m 755 .build/release/$(APP) $(BINDIR)/$(APP)

install-config:
	mkdir -p $(HOME)/.config/polybar-mac
	cp config/config.toml $(HOME)/.config/polybar-mac/config.toml
