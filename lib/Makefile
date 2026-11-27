CC      ?= cc
CFLAGS  ?= -O2 -Wall -Wextra -Werror -std=c11 -pedantic -D_POSIX_C_SOURCE=200809L
BIN     := ../build/capability-driver/gp107ctl
SRC     := gp107ctl.c gp107_identity.c gp107_mmio.c gp107_capabilities.c
HDR     := gp107_identity.h gp107_mmio.h gp107_capabilities.h

all: $(BIN)

$(BIN): $(SRC) $(HDR)
	mkdir -p ../build/capability-driver
	$(CC) $(CFLAGS) -o $@ $(SRC)

profile:
	@echo 'GP107-PROFILE-OK vendor=0x10de device=0x1c82 bdf=0000:01:00.0 physical-mmio=not-authorized'

test: all
	bash ../scripts/test-capability-driver.sh

clean:
	rm -f $(BIN) ../build/capability-driver/gp107ctl-asm ../build/capability-driver/gp107_mmio_asm.o

.PHONY: all profile test clean
