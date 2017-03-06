all: native copy-js

deps: native-deps javascript-deps

.PHONY: javascript copy-js native happy-hack run

stack = stack $(STACK_OPTIONS)

stackjs = $(stack) --stack-yaml stack.ghcjs.yaml

server_directory = testserver

install_root := $(shell stack path --local-install-root)

js_install_root := $(shell $(stackjs) path --local-install-root)

hackmsg = { echo "If build failed while installing 'happy', try 'make happy-hack'"; false; }

happy-hack:
	PATH=$$(dirname $$(stack exec which ghc)):$$(dirname $$(stack exec which happy)):$$PATH \
		$(stackjs) build happy

javascript-deps:
	$(stackjs) build --install-ghc --only-dependencies

javascript:
	@echo $(stackjs) build --install-ghc
	@     $(stackjs) build --install-ghc || $(hackmsg)

copy-js: javascript
	cp $(js_install_root)/bin/example.jsexe/* $(server_directory)/static

native-deps:
	$(stack) build --install-ghc --only-dependencies

native:
	$(stack) build --install-ghc

run: native copy-js
	cd $(server_directory) && $(install_root)/bin/back
