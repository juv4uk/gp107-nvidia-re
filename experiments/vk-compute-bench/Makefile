CC ?= cc
CFLAGS ?= -O2 -Wall -Wextra -std=c11 -I. -I../nvk-compute-smoke

all: vk_compute_bench

# Власний генератор з nvk-compute-smoke; жодного glslang чи vendor-компілятора.
shader.spv.h: ../nvk-compute-smoke/gen_spirv.py
	python3 ../nvk-compute-smoke/gen_spirv.py

vk_compute_bench: vk_compute_bench.c shader.spv.h
	$(CC) $(CFLAGS) -o $@ vk_compute_bench.c -ldl -lrt

run: vk_compute_bench
	bash run.sh

clean:
	rm -f vk_compute_bench shader.spv.h

.PHONY: all run clean
