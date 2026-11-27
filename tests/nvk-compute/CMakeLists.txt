cmake_minimum_required(VERSION 3.20)
project(gp107_nvk_vector_add VERSION 0.1.0 LANGUAGES C)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_C_EXTENSIONS OFF)

find_package(Vulkan 1.3 REQUIRED)
find_program(GLSLANG_VALIDATOR NAMES glslangValidator REQUIRED)
find_program(SPIRV_VAL NAMES spirv-val REQUIRED)

set(SHADER_SOURCE "${CMAKE_CURRENT_SOURCE_DIR}/shaders/vector_add.comp")
set(SHADER_BINARY "${CMAKE_CURRENT_BINARY_DIR}/vector_add.spv")

add_custom_command(
    OUTPUT "${SHADER_BINARY}"
    COMMAND "${GLSLANG_VALIDATOR}" -V --target-env vulkan1.2 -S comp
            "${SHADER_SOURCE}" -o "${SHADER_BINARY}"
    COMMAND "${SPIRV_VAL}" --target-env vulkan1.2 "${SHADER_BINARY}"
    DEPENDS "${SHADER_SOURCE}"
    COMMENT "Compile and validate the GP107 vector-add SPIR-V shader"
    VERBATIM
)
add_custom_target(nvk-shader DEPENDS "${SHADER_BINARY}")

add_executable(nvk-vector-add src/nvk_vector_add.c)
add_dependencies(nvk-vector-add nvk-shader)
target_link_libraries(nvk-vector-add PRIVATE Vulkan::Vulkan)
target_compile_definitions(nvk-vector-add PRIVATE
    _POSIX_C_SOURCE=200809L
    NVK_DEFAULT_SHADER_PATH="${SHADER_BINARY}"
)
if(CMAKE_C_COMPILER_ID MATCHES "GNU|Clang")
    target_compile_options(nvk-vector-add PRIVATE
        -Wall -Wextra -Wpedantic -Wconversion -Wshadow -Wstrict-prototypes
    )
endif()

include(CTest)
if(BUILD_TESTING)
    add_test(NAME nvk-shader-valid
             COMMAND "${SPIRV_VAL}" --target-env vulkan1.2 "${SHADER_BINARY}")
endif()
