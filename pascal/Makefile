FPC       ?= fpc
FPCFLAGS  ?= -O2 -Mobjfpc -Sh -XS -Fu.
FPC_PIN   ?= 3.2.2

TARGET := 01_min_cuinit

all: check-fpc $(TARGET)

check-fpc:
	@got="$$($(FPC) -iV)"; \
	if [ "$$got" != "$(FPC_PIN)" ]; then \
	  echo "FPC-PIN-FAIL expected=$(FPC_PIN) got=$$got" >&2; exit 1; \
	fi; \
	echo "FPC-PIN-OK $$got"

$(TARGET): 01_min_cuinit.pas nv_abi.pas
	$(FPC) $(FPCFLAGS) -o$@ $<

run: all
	./$(TARGET)

test: all
	bash ../scripts/test-pascal-probe.sh

clean:
	rm -f $(TARGET) *.o *.ppu

.PHONY: all check-fpc run test clean
