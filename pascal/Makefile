FPC       ?= fpc
FPCFLAGS  ?= -O2 -Mobjfpc -Sh -XS -Fu.
FPC_PIN   ?= 3.2.2

TARGETS := 01_min_cuinit 02_bar_identity

all: check-fpc $(TARGETS)

check-fpc:
	@got="$$($(FPC) -iV)"; \
	if [ "$$got" != "$(FPC_PIN)" ]; then \
	  echo "FPC-PIN-FAIL expected=$(FPC_PIN) got=$$got" >&2; exit 1; \
	fi; \
	echo "FPC-PIN-OK $$got"

01_min_cuinit: 01_min_cuinit.pas nv_abi.pas
	$(FPC) $(FPCFLAGS) -o$@ $<

02_bar_identity: 02_bar_identity.pas nv_abi.pas nv_device.pas
	$(FPC) $(FPCFLAGS) -o$@ $<

run: all
	./01_min_cuinit
	./02_bar_identity

test: all
	bash ../scripts/test-pascal-probe.sh

clean:
	rm -f $(TARGETS) *.o *.ppu

.PHONY: all check-fpc run test clean
