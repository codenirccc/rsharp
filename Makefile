UNAME_S := $(shell uname -s)

.PHONY: all frontend back-end cdc mini rhir test regress gui clean help

all: frontend back-end cdc mini

frontend:
	cargo build --release --manifest-path frontend/Cargo.toml

back-end:
	bash backend/build.sh

cdc:
	cargo build --release --manifest-path cdc/Cargo.toml

mini:
	bash mini/build.sh

rhir:
	bash rhir/all.sh

test: regress

regress: all
	bash regress.sh

gui:
ifeq ($(UNAME_S),Darwin)
	mkdir -p work/gui/build
	bash ./rsc.sh work/gui/t_core.rsx work/gui/build/t_core
	./work/gui/build/t_core
	bash ./rsc.sh work/gui/p7.rsx work/gui/build/p7
	./work/gui/build/p7 > work/gui/build/p7.txt
	grep -q "hash=-3815621724631491153" work/gui/build/p7.txt
	bash ./rsc.sh work/gui/demo_mac.rsx work/gui/build/demo_mac
	python3 work/gui/check_macho.py work/gui/build/demo_mac || python work/gui/check_macho.py work/gui/build/demo_mac
else
	@echo gui: macOS only here - Windows uses work/gui/run.cmd
endif

clean:
	cargo clean --manifest-path frontend/Cargo.toml
	cargo clean --manifest-path cdc/Cargo.toml
	cargo clean --manifest-path rhir/Cargo.toml
	rm -f backend/*.cmi backend/*.cmx backend/*.o backend/rscb backend/rscb.exe
	rm -f mini/mini mini/mini.exe build/mini_mac build/mini_mac.rsx
	rm -f rhir/tests/*.out.rhir rhir/tests/*.exe
	rm -rf build work/gui/build

help:
	@echo "make            build frontend, back end, cdc and mini"
	@echo "make rhir       build rhirc and run the roundtrip suite"
	@echo "make test       regress examples and the mini suite"
	@echo "make gui        portable GUI checks + a mac demo image (darwin)"
	@echo "make clean      remove every build artifact"
