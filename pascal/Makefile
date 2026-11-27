FPC       ?= fpc
FPCFLAGS  ?= -O2 -Mobjfpc -Sh -XS -Fu.
FPC_PIN   ?= 3.2.2

TARGETS := 01_min_cuinit 02_bar_identity 03_rm_arch_info 04_capability_identity gp107ctl-pascal

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

03_rm_arch_info: 03_rm_arch_info.pas nv_abi.pas nv_device.pas nv_rm.pas
	$(FPC) $(FPCFLAGS) -o$@ $<

04_capability_identity: 04_capability_identity.pas
	$(FPC) $(FPCFLAGS) -o$@ $<

gp107ctl-pascal: check-fpc gp107ctl.pas gp107_identity.pas gp107_mmio.pas gp107_capabilities.pas
	$(FPC) $(FPCFLAGS) -o$@ gp107ctl.pas

run: all
	./01_min_cuinit
	./02_bar_identity
	./03_rm_arch_info

test: all
	bash ../scripts/test-pascal-probe.sh

clean:
	rm -f $(TARGETS) *.o *.ppu

.PHONY: all check-fpc run test clean
