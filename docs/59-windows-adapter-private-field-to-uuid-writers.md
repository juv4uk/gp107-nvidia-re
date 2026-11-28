# 59 — Windows: від приватного поля адаптера до 16 байт `device+0xc06`

Продовження [`docs/56`](56-windows-nvcuda64-uuid-writer-dataflow.md), [`docs/57`](57-windows-cudevicegetuuid-chain.md) і [`docs/58`](58-windows-nvcuda64-dxgdmal-init-chain.md). Дозвіл і межі — [`docs/55`](55-windows-reverse-scope-and-artifacts.md). Тільки статичний Rizin-розбір тих самих двох hach-ів; жодного процесу, ioctl чи GPU-дії не виконувалося.

Evidence: `evidence/windows-20261128/nvcuda64-private-field-to-uuid-writers.json`.

## 0. Суб'єкти

| Бінарник | SHA-256 | Роль |
|---|---|---|
| `nvcuda64.dll`, `32.0.15.8278` | `af853a5b0f3ce3eedc297c66cf5e03307112aa31c714b82479a2ae841c92d407` | Writer A/B, об'єкт `0x28f8`, `cuDeviceGetUuid` |
| `nvdxgdmal64.dll` | `9353f1b598f2c8649a33b59db011763474e8ef2a6749385a23d9f78af25feceb` | `dxgdmal*`, `D3DKMTQueryAdapterInfo`, нормалізація даних адаптера |

## 1. Замкнений ланцюг для Writer A

```
cuInit -> ... -> [iface+0xc8] = dxgdmalGetAdapterCallbacks       (docs/58)
        -> table[0x18] = 0x180005540                             (docs/58)
        -> QueryAdapterInfo(type=0xc115) -> private buffer r15
        -> 0x180002080 (нормалізація)
        -> 0x1800013a0: private+0x1442+i*0x10 -> object+0x1f8+i*0x198
        -> memcpy-like копія normalization buffer -> r12 (об'єкт 0x28f8)
        -> 0x180409010 (Writer A): object+0x1f8+i*0x198 -> device+0xc06
        -> cuDeviceGetUuid: device+0xc06 -> CUuuid                 (docs/57)
```

Кожен стрілка нижче має власний Evidence ID; це не гіпотеза про ім'я поля, а статично простежена адресація.

## 2. Що саме запитується і куди потрапляє

`0x180005540` викликає `0x1800050c0`, який формує `D3DKMT_QUERYADAPTERINFO`-подібний блок `{ecx, edx, r8, r9d, 0}` і викликає вказівник `[0x18008d088]` (`D3DKMTQueryAdapterInfo`, встановлений у docs/58). Безпосередньо перед цим `r9d=0xc115`, `r8=r15`, `edx=0`, `ecx=r14d` (`ev_65eafe01…`, `ev_0820887c…`). Число `0xc115` наведено як спостережену константу: публічний D3DKMT-заголовок у цьому lane не відкривався.

Після успішного запиту `rdx=r15` (приватний буфер адаптера), `rcx=&var_2a48h`, і відбувається виклик `0x180002080` (`ev_ca6b40e6…`). Це не новий ioctl, а перетворення вже отриманого буфера у вкладений об'єкт.

## 3. Два різні 16/32-байтні поля — не плутати їх

### 3.1. Пер-адаптерні блоки, які справді йдуть у `device+0xc06`

Функція `0x1800013a0` — єдиний прямий caller якої є `0x180002080` (`ev_4c0cc8d7…`, `ev_7ca6b2ca…`) — робить таке (`ev_f2ede7a3…`):

| Адреса | Дія |
|---|---|
| `0x1800013a2` | `eax = [private+0x3c69]` — число адаптерів |
| `0x1800013ab` | `[object+0x1e8] = eax` (мінімум 1) |
| `0x1800013d3` | `rcx = i*0x198` |
| `0x1800013dd` | `r10 = i*0x10` |
| `0x1800013e1` | `[object+0x1f0] = 0x198` — stride запису |
| `0x1800013ed`–`0x1800013f6` | `xmm0 = [private+0x1442+i*0x10]` → `[object+0x1f8+i*0x198]` |
| `0x180001975` | цикл, поки `i < [object+0x1e8]` |

Лічильник `[object+0x1e8]` і stride `0x198` збігаються з тим, що Writer A читає `[r8+0x1e8]` і рахує `i*0x198` (`docs/56`). Це замикає ланцюг.

### 3.2. Окреме 32-байтне поле `+0xa0/+0xb0`

Паралельно `0x180002080` бере 32 байти з `private+0xc095` / `private+0xc0a5` і кладе їх у `[desc+0xa0]` / `[desc+0xb0]` (`ev_5d3663cc…`). У Writer A ці 32 байти з об'єкта `+0xa0` копіюються в локальний буфер `var_8d7h` (`0x1804093dd`–`0x1804093f2`, `ev_a10db552…`, `ev_cb90768f…`).

**Важливо:** цей локальний буфер **не** є джерелом запису в `device+0xc06`. Джерелом є `[rcx-0xf0]`, де `rcx=[var_998h]`. Розрахунок у `0x1804091e9`–`0x1804091fc` дає `var_998h = object+0x2e8+i*0x198`, отже `[rcx-0xf0] = object+0x1f8+i*0x198` (`ev_78e8cc38…`, `ev_c01c4887…`). Тому 16 байти в `device+0xc06` походять із §3.1, а не з §3.2. Чи пов'язане поле §3.2 з UUID — **UNPROVEN**.

## 4. Як нормалізований об'єкт потрапляє у Writer A

Після нормалізації `0x180005540` виконує (`ev_ca6b40e6…`, `ev_9f8789d9…`):

- `r8 = [var_2a48h]` — розмір, записаний ще на `0x18000563f` (`ev_f3e458b4…`);
- `rdx = &var_2a48h`;
- `rcx = r12`;
- `call 0x18002d2a0` — memcpy-подібна копія (`dest=rcx`, `src=rdx`, `size=r8`, `ev_b71ddd08…`).

За [`docs/58`](58-windows-nvcuda64-dxgdmal-init-chain.md), `r12` — це об'єкт `0x28f8`, виділений у `nvcuda64.dll` і заповнений через `[iface+0xc8]`. Саме він далі передається як `arg3` Writer A. Отже об'єкт, у який `0x1800013a0` пише `+0x1f8+i*0x198`, і об'єкт, з якого Writer A бере `+0x1f8+i*0x198`, — той самий об'єкт `0x28f8`.

Фінальна копія (`ev_cc84ca9b…`): `0x1804096e8: movups xmm0,[rcx-0xf0]` → `0x1804096ef: movups [rax+0xc06],xmm0`.

**Статус: `statically proven`** для всього ланцюга адресації й копіювання 16 байт у Writer A.

## 5. Writer B: доведено writer, не доведено джерело

Writer B `0x18036d300` (`ev_a9683dc1…`):

- `0x18036d627`: `[rbx+0x5e49] |= 1` — прапорець, який `cuDeviceGetUuid_v2` перевіряє в docs/57;
- `0x18036d637`–`0x18036d645`: `[rdi+0x481]` → `[rbx+0xc27]`;
- `0x18036d64c`–`0x18036d661`: сусідні байти `[rdi+0x471]`/`[rdi+0x470]` → `[rbx+0xc16]`/`[rbx+0xc26]`.

Функція реєструється як слот `+0x6c98` (`docs/56`), а прямих викликів до неї не знайдено: лише DATA-посилання з `0x18036bb70` (`ev_017ffc95…`) і з самої таблиці методів `0x18036f270` (`ev_a34fd0bd…`, `ev_16bbf5e0…`). Спроба простежити indirect caller була перервана перезапуском REA; нових запитів після цього не робилося.

**Статус: `statically proven`** для самої копії й прапорця. **UNPROVEN**: походження `[rdi+0x481]` і те, що воно живиться з того самого нормалізованого буфера адаптера.

## 6. Що залишається недоведеним

| Твердження | Статус |
|---|---|
| `QueryAdapterInfo(type=0xc115)` заповнює приватний буфер `r15` | `statically proven` |
| `0x1800013a0`: `private+0x1442+i*0x10` → `object+0x1f8+i*0x198`, stride `0x198` | `statically proven` |
| Нормалізований буфер копіюється в об'єкт `0x28f8`, який іде у Writer A | `statically proven` |
| Writer A: `object+0x1f8+i*0x198` → `device+0xc06` | `statically proven` |
| Окреме поле `private+0xc095/+0xc0a5` → `object+0xa0/+0xb0` → `var_8d7` | `statically proven`, але не джерело `device+0xc06` |
| Writer B: `rdi+0x481` → `device+0xc27`, `+0x5e49 |= 1` | `statically proven` |
| Ці 16 байти є саме UUID GPU | `UNPROVEN` |
| Кінцевий виробник байтів: RM / NVML / D3DKMT / PCI / VBIOS | `UNPROVEN` |
| Зв'язок Writer B із тим самим приватним буфером | `UNPROVEN` |
| Хто пише заповнені об'єкти в `[0x182002520+idx*8]` | `UNPROVEN` |
| `BDF_TO_RM_GPU_ID` і відповідність Linux `docs/41` | `UNPROVEN` |
| Виконання будь-якого шляху на цій машині | `NOT RUN` |

## 7. Межі доказів

Ghidra двічі не завершив імпорт/аналіз 34 MB DLL (`provider_timeout`), тому Ghidra-xrefs не заявляються. Rizin не зберігає аналіз між викликами, `axt` виконувався з `aaa` у тій самій команді. Частина `pd`-вікон починалася серединою інструкції; висновки звірено з вирівняними `af/pdf` і явними зрізами адрес. `axt` для `0x1800013a0` і `0x18036d300` супроводжувався ESIL `Cannot peek` та `bin_file_strings` warnings — перелічені xrefs це не спростовує. Пошук прямого виклику `0x180005540 → 0x1800013a0` дав порожній результат; шлях іде через `0x180002080`.

Жодного RM/UVM/D3DKMT ioctl, `cuInit`, `cuDeviceGetUuid`, CUDA/Vulkan/OpenGL init, GPU submit, MMIO, firmware, reboot, tag чи release не виконувалося. Наступний безпечний крок — знайти producers полів `private+0x1442` і `rdi+0x470/0x481`, лишаючись у статичному Rizin-розборі тих самих hach-ів.
