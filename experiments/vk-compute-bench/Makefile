CC ?= cc
CFLAGS ?= -O2 -Wall -Wextra -std=c11 -I. -I../nvk-compute-smoke

MATRIX_SHADERS = matrix-shaders/shader_ls32.spv.h \
                 matrix-shaders/shader_ls64.spv.h \
                 matrix-shaders/shader_ls128.spv.h \
                 matrix-shaders/shader_ls256.spv.h

all: vk_compute_bench vk_compute_matrix vk_transfer_bench

# Власний генератор з nvk-compute-smoke; жодного glslang чи vendor-компілятора.
shader.spv.h: ../nvk-compute-smoke/gen_spirv.py
	python3 ../nvk-compute-smoke/gen_spirv.py

vk_compute_bench: vk_compute_bench.c shader.spv.h
	$(CC) $(CFLAGS) -o $@ vk_compute_bench.c -ldl -lrt

# Експериментальна матриця: окремий бінарник, канонічний не перезаписується.
matrix-shaders/shader_ls%.spv.h: ../nvk-compute-smoke/gen_spirv.py
	mkdir -p matrix-shaders
	python3 ../nvk-compute-smoke/gen_spirv.py --local-size $* --out $@ \
	  --symbol spirv_ls$* --label VECTOR-ADD-LS$*

vk_compute_matrix: vk_compute_matrix.c $(MATRIX_SHADERS)
	$(CC) $(CFLAGS) -o $@ vk_compute_matrix.c -ldl -lrt

# DEVICE_LOCAL staging/compute/readback phases; separate fences per phase.
vk_transfer_bench: vk_transfer_bench.c shader.spv.h
	$(CC) $(CFLAGS) -o $@ vk_transfer_bench.c -ldl -lrt

run-transfer: vk_transfer_bench
	BENCH_BIN=$PWD/vk_transfer_bench bash run.sh

run: vk_compute_bench
	bash run.sh

run-matrix: vk_compute_matrix
	BENCH_BIN=$PWD/vk_compute_matrix bash run.sh

clean:
	rm -f vk_compute_bench vk_compute_matrix vk_transfer_bench shader.spv.h
	rm -rf matrix-shaders

.PHONY: all run run-matrix run-transfer clean
