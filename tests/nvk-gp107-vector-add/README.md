# NVK GP107 vector-add harness

<!-- SPDX-License-Identifier: LicenseRef-Volnist -->

**Стан:** clean-room source/build harness. PHYSICAL_GPU_TEST=NOT_RUN.
**Ціль:** NVIDIA GeForce GTX 1050 Ti, Pascal GP107, PCI 10de:1c82.

Це невеликий Vulkan compute smoke test, а не graphics benchmark і не загальна сертифікація Vulkan. Успішний фізичний запуск має довести, що тест обрав саме GPU за vendor/device ID та PCI BDF, отримав Mesa NVK driver ID, створив compute queue, виконав vector-add dispatch, дочекався fence і перевірив кожен елемент та контрольну суму.

## Межі доказів

- Compile-only CI доводить лише, що C-код компілюється, GLSL перетворюється у SPIR-V, SPIR-V проходить spirv-val, а deny-by-default аргументні ворота відмовляють до Vulkan instance/device enumeration.
- CI не запускає executable, не створює Vulkan instance, не перелічує фізичні пристрої та не звертається до GPU.
- Старий upstream дослідницький текст для Mesa 26.3.1 не є доказом для WSM. H170 WSM profile pin-ить Mesa 26.2.6; його source eligibility занотовано окремо у WSM Desktop. Відмінності в discovery, channel setup і queue init потрібно перевірити саме на точному package/source pair перед будь-яким фізичним запуском.
- Фізичний compute witness у docs/14 — окреме історичне свідчення зі своїм Mesa/kernel контекстом. Не приписувати його цьому harness чи WSM Guix profile.

## Build та перевірка без GPU

Потрібні Vulkan headers/loader development files, C11 compiler, glslangValidator і spirv-tools.

\`\`\`sh
glslangValidator -V --target-env vulkan1.1 -o vector_add.spv vector_add.comp
spirv-val --target-env vulkan1.1 vector_add.spv
spirv-dis vector_add.spv -o vector_add.spvasm
cc -std=c11 -O2 -Wall -Wextra -Wpedantic -Werror \\
  -o nvk-vector-add nvk-vector-add.c -lvulkan
sha256sum nvk-vector-add.c vector_add.comp vector_add.spv vector_add.spvasm nvk-vector-add
\`\`\`

GitHub Actions workflow робить ці кроки на ubuntu-24.04, після чого перевіряє чотири negative CLI cases. Очікується exit 4 для відсутнього acknowledgment, браку режиму, конфлікту enumeration/submit та exit 2 для недозволеного розміру роботи. В усіх цих cases Vulkan instance не створюється.

## Два незалежні acknowledgment gates

Executable за замовчуванням відхиляє запуск до vkCreateInstance і vkEnumeratePhysicalDevices:

- --allow-temp-gr-channel-init підтверджує, що NVK discovery може відкрити Nouveau render node з O_RDWR, ініціалізувати VM/NVIF і створити/звільнити тимчасовий GR channel та підканали. Це не є строго read-only.
- --enumeration-only дозволяє лише discovery та перевірку GP107 PCI/BDF і Mesa NVK driver ID; не створює VkDevice, queue або compute submit. Але temporary GR channel side effects залишаються.
- --allow-gpu-submit є окремим acknowledgment для VkDevice/queue, shader dispatch, fence wait та readback. Його не можна поєднувати з --enumeration-only.

Жоден прапорець не замінює окремого погодження власника, issue #18 safety gate, точного source/package provenance чи rollback plan.

## Фізичний запуск — не виконувати без окремого погодження

Перед будь-яким запуском мають бути виконані всі умови:

1. Issue #18 закриває conditional FIFO/non-stall review або власник письмово погоджує обмежений діагностичний boot.
2. Зафіксовані точні kernel package/source/patch set та Mesa package/source commit/hash саме того середовища, де працюватиме harness.
3. Є окремий boot/Live USB із перевіреним поверненням до поточного proprietary NVIDIA R580; не змінювати постійний GRUB, initramfs чи встановлений driver.
4. lspci -Dnnk -d 10de:1c82 показує цільовий BDF і Kernel driver in use: nouveau; proprietary NVIDIA KMD не повинен одночасно володіти GPU.
5. Власник окремо погодив спершу enumeration-only, а потім — лише за успіху й перегляду evidence — compute submit.

BDF потрібно визначати динамічно з lspci; не копіювати адресу з прикладу. Не запускати vulkaninfo, vkEnumeratePhysicalDevices або цей executable як пасивний preflight: сам NVK enumeration може мати channel/VM/NVIF side effects. Не робити MMIO/BAR poking, firmware flashing, RM/UVM ioctl, ручний reset або reboot без окремого погодження.

Команди нижче є лише формою майбутнього тесту, а не дозволом на запуск:

\`\`\`sh
BDF="$(lspci -Dnn -d 10de:1c82 | awk 'NR==1 {print $1}')"
test -n "$BDF" || exit 2

# Лише після окремого дозволу та успішного issue #18 gate:
DRI_BDF="$(printf '%s' "$BDF" | tr ':.' '__')"
DRI_PRIME_VALUE="pci-$DRI_BDF!"

DRI_PRIME_DEBUG=1 DRI_PRIME="$DRI_PRIME_VALUE" \\
  ./nvk-vector-add --bdf "$BDF" --allow-temp-gr-channel-init \\
  --enumeration-only

# Окреме рішення власника потрібне ще й для GPU submit:
DRI_PRIME_DEBUG=1 DRI_PRIME="$DRI_PRIME_VALUE" \\
  ./nvk-vector-add --bdf "$BDF" --allow-temp-gr-channel-init \\
  --allow-gpu-submit --elements 257 --spv vector_add.spv
\`\`\`

Зберігати точні команди, stdout/stderr, exit code, kernel/Mesa provenance, lspci -Dnnk, журнал ядра та SHA-256 усіх harness artifacts. NVK_GP107_VECTOR_ADD_PASS означатиме лише успішність цього конкретного shader на вибраному GP107; це не доводить повну Vulkan, graphics, OpenCL, video, reclocking чи performance support.

## Статус

- SOURCE_BUILD_CI: окрема перевірка compile/SPIR-V/negative CLI.
- PHYSICAL_GPU_TEST: NOT_RUN.
- WSM_H170_MESA_PIN: 26.2.6; physical WSM NVK acceptance не встановлено.
- Не змішувати цей harness із NVIDIA proprietary RM/UVM дослідженням або з попереднім фізичним witness із docs/14.
