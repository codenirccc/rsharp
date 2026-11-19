UNAME_S := $(shell uname -s)

ifeq ($(UNAME_S),Darwin)
HOST := macos
else ifeq ($(UNAME_S),Linux)
HOST := linux
else
HOST := windows
endif

HOST_BIN := build/rmake
ifeq ($(HOST),windows)
HOST_BIN := build/rmake.exe
endif

.PHONY: all tools frontend back-end cdc mini rmake build test regress dist win linux mac clean help

all: tools build

tools: frontend back-end cdc mini rmake

frontend:
	cargo build --release --manifest-path frontend/Cargo.toml

back-end:
	bash backend/build.sh

cdc:
	cargo build --release --manifest-path cdc/Cargo.toml

mini:
	bash mini/build.sh

rmake:
	./rsc.sh tools/rmake/main.rsx $(HOST_BIN)
	./rsc.sh -t linux tools/rmake/main.rsx build/rmake_linux
	./rsc.sh -t macos tools/rmake/main.rsx build/rmake_mac

build: tools
	./rmake.sh build

win: tools
	./rmake.sh build --tgt windows

linux: tools
	./rmake.sh build --tgt linux

mac: tools
	./rmake.sh build --tgt macos

test: regress

regress: tools
	bash regress.sh

dist: tools
	bash dist.sh

clean:
	rm -rf build .rmake dist
	cargo clean --manifest-path frontend/Cargo.toml
	cargo clean --manifest-path cdc/Cargo.toml
	cargo clean --manifest-path rhir/Cargo.toml
	rm -f backend/*.cmi backend/*.cmx backend/*.o backend/rscb backend/rscb.exe
	rm -f backend/rscvm backend/rscvm.exe
	rm -f mini/mini mini/mini.exe
	rm -f rhir/tests/*.out.rhir rhir/tests/*.exe
	rm -rf dist build work/gui/build

help:
	@echo "make          build the toolchain, then every target in RMakefile"
	@echo "make tools    build front end, back end, cdc, mini and rmake"
	@echo "make build    run rmake build"
	@echo "make win      rmake build for windows"
	@echo "make linux    rmake build for linux"
	@echo "make mac      rmake build for macos"
	@echo "make test     regress examples, the mini suite and rmake"
	@echo "make dist     stage the download set under dist/"
	@echo "make clean    remove every build artifact"
