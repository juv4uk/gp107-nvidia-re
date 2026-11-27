CC ?= cc
CFLAGS ?= -O2 -Wall -Wextra -std=c11 -I.

all: nvk_compute_smoke

shader.spv.h: gen_spirv.py
	python3 gen_spirv.py

shader_noop.spv.h: gen_spirv.py
	python3 gen_spirv.py --noop

nvk_compute_smoke: nvk_compute_smoke.c vk_min.h shader.spv.h
	$(CC) $(CFLAGS) -o $@ nvk_compute_smoke.c -ldl

nvk_compute_smoke_noop: nvk_compute_smoke.c vk_min.h shader_noop.spv.h
	$(CC) $(CFLAGS) -DSMOKE_NOOP_SHADER -o $@ nvk_compute_smoke.c -ldl

run: nvk_compute_smoke
	bash run.sh

run-negative: nvk_compute_smoke_noop
	bash run-negative.sh

clean:
	rm -f nvk_compute_smoke nvk_compute_smoke_noop

.PHONY: all run run-negative clean
