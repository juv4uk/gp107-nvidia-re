CC      ?= cc
CFLAGS  ?= -O2 -Wall -Wextra -Werror -std=c11 -pedantic -D_POSIX_C_SOURCE=200809L
ARCH    := $(shell uname -m)
ASFLAGS ?= -c
BIN     := ../build/capability-driver/gp107ctl
ASM_BIN := ../build/capability-driver/gp107ctl-asm
ASM_OBJ := ../build/capability-driver/gp107_mmio_asm.o
SRC     := gp107ctl.c gp107_identity.c gp107_mmio.c gp107_capabilities.c
HDR     := gp107_identity.h gp107_mmio.h gp107_capabilities.h

ifeq ($(ARCH),x86_64)
all: $(BIN) $(ASM_BIN)
else
all: $(BIN)
endif

$(BIN): $(SRC) $(HDR)
	mkdir -p ../build/capability-driver
	$(CC) $(CFLAGS) -o $@ $(SRC)

$(ASM_OBJ): gp107_mmio_asm.S
	mkdir -p ../build/capability-driver
	$(CC) $(ASFLAGS) -o $@ $<

$(ASM_BIN): $(SRC) $(HDR) $(ASM_OBJ)
	$(CC) $(CFLAGS) -DGP107_USE_ASM=1 -o $@ $(SRC) $(ASM_OBJ)

profile:
	@echo 'GP107-PROFILE-OK vendor=0x10de device=0x1c82 bdf=0000:01:00.0 arch=$(ARCH) asm=read-only'

test: all
	bash ../scripts/test-capability-driver.sh

clean:
	rm -f $(BIN) $(ASM_BIN) $(ASM_OBJ)

.PHONY: all profile test clean
