CC ?= cc
GLSLC ?= glslc
GLSLANG_VALIDATOR ?= glslangValidator

CFLAGS ?= -O2 -g
CFLAGS += -std=c11 -Wall -Wextra -Wpedantic -D_POSIX_C_SOURCE=200809L
LDLIBS += -lvulkan

TARGET := gp107-vk-compute-smoke
SHADER := vector_add.comp
SPIRV := vector_add.comp.spv

.PHONY: all shader run clean

all: $(TARGET) $(SPIRV)

$(TARGET): gp107_vk_compute_smoke.c
	$(CC) $(CFLAGS) $(CPPFLAGS) -o $@ $< $(LDFLAGS) $(LDLIBS)

$(SPIRV): $(SHADER)
	@if command -v "$(GLSLC)" >/dev/null 2>&1; then \
		"$(GLSLC)" --target-env=vulkan1.2 -fshader-stage=compute -O0 -o "$@" "$<"; \
	elif command -v "$(GLSLANG_VALIDATOR)" >/dev/null 2>&1; then \
		"$(GLSLANG_VALIDATOR)" -V --target-env vulkan1.2 -S comp -o "$@" "$<"; \
	else \
		echo "GP107-VK-COMPUTE-NOT-AVAILABLE reason=missing-glslc-or-glslangValidator" >&2; \
		exit 77; \
	fi

shader: $(SPIRV)

run: all
	./run-gp107.sh "./$(TARGET)" "./$(SPIRV)"

clean:
	rm -f "$(TARGET)" "$(SPIRV)"
