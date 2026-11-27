# GP107: матриця можливостей і станів доказу

Цей документ описує лише дослідницьку конфігурацію GP107 / R580, зафіксовану
в цьому репозиторії. Він не є драйверною специфікацією, не задає target ABI
і не змінює контракт `wsm-os-lisp`.

## Середовище базових свідків

| Параметр | Зафіксоване значення |
|---|---|
| GPU | NVIDIA GP107, GeForce GTX 1050 Ti |
| PCI ID | `10de:1c82` |
| Архітектура виконання | Pascal, SM 6.1 |
| Драйвер | R580 `580.196.11` |
| Ядро | `7.2.15+kali-amd64` |
| Пробник | FPC 3.2.2, x86-64 Linux |

Висновки за межами цієї конфігурації потребують окремого runtime-свідка.

## Матриця можливостей

| Можливість / твердження | Інтерфейс або джерело | Стан доказу | Межа висновку |
|---|---|---|---|
| PCI vendor/device identity | `NV_ESC_CARD_INFO` + PCI config sysfs | **runtime-proven** | Два незалежні джерела збігаються для GP107 на базовій машині |
| PCI BDF і BAR0 base/size | `NV_ESC_CARD_INFO` + PCI config sysfs | **runtime-proven** | Підтверджено ідентичність і BAR resource; це не доступ до MMIO |
| Вибір GP107 за PCI ID і minor | `SelectTargetCard` + `GpuDevicePath` | **в master; локальний runtime повторити** | Перевіряє унікальний PCI ID і межу minor; додатковий PCI-config cross-check входить до цього PR |
| RM GPU-ID enumeration | `GPU_GET_PROBED_IDS` | **новий fail-closed gate; runtime очікується** | Пробник відхиляє нуль або кілька ID, бо відповідність RM gpu_id ↔ PCI BDF ще не доведена |
| RM architecture info | `NV_ESC_RM_CONTROL`, `NV2080_CTRL_CMD_MC_GET_ARCH_INFO` | **runtime-proven** | Числа прочитані через RM; зіставлення з іменами сімейства/реалізації має окремий статус interpretation |
| `NV_PMC_BOOT_0` read | BAR0 / MMIO | **UNPROVEN** | Значення регістра на базовій машині не прочитане |
| BAR0 open непривілейованим користувачем | sysfs `resource0`, `O_RDONLY` | **runtime-proven: OPEN_DENIED / EACCES** | Фіксує лише відмову open для цього UID; не доводить причину чи ексклюзивне володіння BAR |
| BAR0 mmap з root | sysfs `resource0`, `PROT_READ` + `MAP_SHARED` | **runtime-proven: MMAP_DENIED / EINVAL** | Фіксує відмову mmap; errno не встановлює, який саме kernel check відмовив |
| UVM initialization | `/dev/nvidia-uvm`, UVM ioctl | **спостережено через NVIDIA driver** | Не є незалежною реалізацією UVM |
| Device memory allocation | RM `NV_ESC_RM_ALLOC` + UVM | **runtime-observed через CUDA driver** | Clean-room allocator не реалізовано |
| Kernel launch | `cuLaunchKernel`, mapped channel/pushbuffer path | **частково досліджено** | Trace показав відсутність ioctl безпосередньо в launch-виклику; точний channel ABI та doorbell не відтворені |
| Pushbuffer / command submission | RM resources, mapped memory, MMIO | **частково досліджено / незалежно не реалізовано** | Не є доказом готовності власного submission path |
| DMA та GPU VA space | RM + UVM | **частково досліджено через vendor driver** | Немає власної реалізації DMA, IOMMU mapping чи GPU page tables |
| Власний незалежний GPU driver | bare-metal / kernel driver | **не реалізовано** | Поточні probes залежать від встановленого NVIDIA kernel driver і його device nodes |

## Правила читання статусів

- **runtime-proven** — конкретне значення або поведінку спостережено під час запуску на вказаному обладнанні та версії драйвера.
- **runtime-observed через NVIDIA driver** — спостережено vendor path; це не означає, що наш код реалізує відповідний механізм.
- **runtime-denied** — конкретний доступ був відхилений; причина не виводиться без окремого доказу.
- **частково досліджено** — відомі зовнішні ознаки або частина послідовності, але не повний протокол.
- **UNPROVEN** — достатнього свідчення немає; гіпотези не підвищуються до фактів.

## Наступні свідки

1. Повторно прогнати всі три FPC probes після оновлення RM target selection і PCI config cross-check.
2. Окремо дослідити RM object lifecycle: allocate/free у зворотному порядку та cleanup після часткової відмови.
3. Дослідити channel/context initialization і буфери команд перед відтворенням pushbuffer submission.
4. Окремо визначити межі BAR0 access, не змінюючи read-only fail-closed профіль.
5. Не переносити жоден результат до target ABI `wsm-os-lisp` без owner-рішення та contract review.
