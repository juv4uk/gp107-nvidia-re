CC      ?= cc
CFLAGS  ?= -O2 -Wall -Wextra -Werror -std=c11 -pedantic -D_POSIX_C_SOURCE=200809L
BIN     := ../build/capability-driver/gp107ctl
SRC     := gp107ctl.c gp107_identity.c gp107_mmio.c
HDR     := gp107_identity.h gp107_mmio.h

all: $(BIN)

$(BIN): $(SRC) $(HDR)
	mkdir -p ../build/capability-driver
	$(CC) $(CFLAGS) -o $@ $(SRC)

test: all
	bash ../scripts/test-capability-driver.sh

clean:
	rm -f $(BIN)

.PHONY: all test clean
