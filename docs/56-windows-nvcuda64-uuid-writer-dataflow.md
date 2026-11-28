# 56 — Windows `nvcuda64.dll`: dataflow двох writer-ів `device+0xc06/0xc27`

Продовження [`docs/45`](45-windows-uvm-uuid-comparison.md) на **реально встановленому** бінарнику з цієї Windows-машини. Дозвіл і точний hach зафіксовані в [`docs/55`](55-windows-reverse-scope-and-artifacts.md). Тут немає runtime, ioctl, GPU-submit чи пропрієтарного source. Код не запускався — лише статичний Rizin-розбір.

## 0. Суб'єкт

| Властивість | Значення |
|---|---|
| Файл | `nvcuda64.dll`, `32.0.15.8278` |
| SHA-256 | `af853a5b0f3ce3eedc297c66cf5e03307112aa31c714b82479a2ae841c92d407` |
| ImageBase у Rizin | `0x180000000` |
| Tool | Rizin через REA, read-only |
| Evidence | `evidence/windows-20261128/nvcuda64-writer-dataflow.json` |

Усі адреси нижче — VA. Змішувати їх з офсетами з Linux `libcuda.so.580.196.11` (`docs/41`) **не можна**: це інші бінарники.

## 1. Writer A — шлях до `device+0xc06`

`fcn.180409010` (`0x180409010`) має сигналтуру `(rcx, rdx, r8, r9)`.

1. `r8` — вказівник на об'єкт-контейнер; число записів береться з `[r8+0x1e8]` (`0x18040903d`).
2. У циклі покажчик на поточний запис рахується так (`0x1804091e9`–`0x1804091fc`):
   `rsi + 0x2e8 + i*0x198` → `[rsp+0x40]`. Evidence `ev_63dd03a2…`.
3. Безпосередньо перед записом (`0x1804096e3`–`0x1804096ef`):
   `rcx = [rsp+0x40]`; `xmm0 = [rcx-0xf0]`; `[device+0xc06] = xmm0`.
   Тобто джерело — `[rsi+0x1f8+i*0x198]`, а приймач — об'єкт із `[rsp+0x28]`.
   Evidence `ev_f550af5d…`.
4. Цей самий приймач додається в таблицю `[rbp+r15*8+0x730]` (`0x1804096fb`).

**Статус:** `statically proven` для арифметики адрес і копіювання 16 байт. `UNPROVEN`: тип цих байт, походження й те, що це саме UUID.

## 2. Хто формує `r8` для Writer A

Прямий caller — `0x18040a09b` (`call 0x180409010`) у функції з entry `0x180409f50`:

- `0x180409f75`: `ecx = 0x28f8`;
- `0x180409f82`: `call 0x1817d6e18` — виділення об'єкта розміром `0x28f8`;
- `0x180409f87`–`0x180409f99`: `rax = [0x182004658]`, `rdx = &[rsp+0x68]`, `rcx = rbp`, виклик `qword [rax+0xc8]`;
- `0x180409fa0`: `rbx = rax` (виділений об'єкт), далі `[rbx] = 0x28f8`;
- `0x18040a076`: `r8 = rbx` перед викликом Writer A.

Evidence `ev_a89cf652…` і `ev_3008c946…`.

**Статус:** `statically proven` — `arg3` Writer A є об'єктом розміром `0x28f8`, заповненим через віртуальний метод `[iface+0xc8]`. **UNPROVEN**: яка саме функція стоїть у `[iface+0xc8]`, і чи надходить звідти UUID.

## 3. Writer B — шлях до `device+0xc27`

Функція `0x18036d300` має `(rcx, rdx)`: `rdi = rcx` (джерело), `rbx = rdx` (приймач).

- `0x18036d627`: `or byte [rbx+0x5e49], 0x01` — той самий прапорець альтернативного зсуву, що й у `docs/45`;
- `0x18036d637`–`0x18036d645`: `xmm0 = [rdi+0x481]`, `[rbx+0xc27] = xmm0`;
- `0x18036d64c`–`0x18036d653`: `[rdi+0x471]` → `[rbx+0xc16]`;
- `0x18036d65a`–`0x18036d661`: байт `[rdi+0x470]` → `[rbx+0xc26]`.

Evidence `ev_a971dd6c…`.

Ця функція встановлюється як слот у таблиці методів: `0x18036bb70`: `lea rax,[0x18036d300]`; `mov [rcx+0x6c98], rax` (evidence `ev_89a7edba…`).

**Статус:** `statically proven` для writer і для реєстрації в слоті `+0x6c98`. **UNPROVEN**: хто викликає цей слот у рантаймі й звідки береться `arg1+0x481`.

## 4. Що це змінює, а що ні

| Питання | Статус |
|---|---|
| Writer A копіює 16 байт із `arg3+0x1f8+i*0x198` у `device+0xc06` | `statically proven` |
| Writer B копіює 16 байт із `arg1+0x481` у `device+0xc27` | `statically proven` |
| `arg3` — об'єкт `0x28f8`, заповнений через `[iface+0xc8]` | `statically proven` |
| Writer B зареєстрований у слоті `+0x6c98` | `statically proven` |
| Джерельні 16 байт є UUID GPU | `UNPROVEN` |
| Походження від RM/NVML/D3DKMT/PCI BDF | `UNPROVEN` |
| `BDF_TO_RM_GPU_ID` | `UNPROVEN` |
| Виконання будь-якого з цих шляхів | `NOT RUN` |

## 5. Наступний безпечний крок

Знайти реалізацію віртуального методу `[iface+0xc8]` і простежити, хто записує в `arg3+0x1f8`. Це все статичний Rizin-розбір того самого hach-у; не потребує запуску драйвера. Якщо джерело виявиться ioctl-залежним, результат лишається `UNPROVEN` без operational approval.

Жодного RM/UVM ioctl, `cuInit`, CUDA/Vulkan, GPU submit, MMIO, firmware, reboot, tag чи release не виконувалося.
