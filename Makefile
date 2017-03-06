all: native copy-js

deps: native-deps javascript-deps

.PHONY: javascript copy-js build-tools native happy-hack run

stack = stack --install-ghc $(STACK_OPTIONS)

stackjs = $(stack) --stack-yaml stack.ghcjs.yaml

server_directory = testserver

install_root := $(shell stack path --local-install-root)

js_install_root := $(shell $(stackjs) path --local-install-root)

hackmsg = { echo "If build failed while installing 'happy', try 'make happy-hack'"; false; }

build-tools:
	$(stack) build alex happy hscolour gtk2hs-buildtools

happy-hack:
	PATH=$$(dirname $$(stack exec which ghc)):$$(dirname $$(stack exec which happy)):$$PATH \
		$(stackjs) build happy

javascript-deps: build-tools
	$(stackjs) build --only-dependencies

javascript:
	@echo $(stackjs) build
	@     $(stackjs) build || $(hackmsg)

copy-js: javascript
	cp $(js_install_root)/bin/example.jsexe/* $(server_directory)/static

native-deps: build-tools
	$(stack) build --only-dependencies

native:
	$(stack) build

run: native copy-js
	cd $(server_directory) && $(install_root)/bin/back
