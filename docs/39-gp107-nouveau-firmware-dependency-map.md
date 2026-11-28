# 39 — GP107: карта Nouveau firmware dependencies та межа Free/Compatibility

## Мета й статус

Це **source-only dependency map** для NVIDIA GP107 / GTX 1050 Ti (10de:1c82).
Він потрібний, щоб не змішувати upstream Nouveau з власне вільним WSM Free
профілем і окремим opt-in Compatibility профілем.

- **SOURCE_CONFIRMED**: шлях оголошений у pinned Linux source або явно записаний у linux-firmware/WHENCE.
- **SOURCE_CANDIDATE**: source оголошує файл/версію, але це саме по собі не доводить, що конкретний boot його запросив чи використав.
- **RUNTIME_NOT_PAIRED**: ще немає зіставлення наведеного Linux source snapshot із фактичним nouveau.ko, завантаженим на окремому Kali witness host.
- **NOT_TESTED_H170**: жоден пункт тут не є доказом функціональності WSM на GA-H170-Gaming 3.

Жодного firmware blob, vendor source або декомпільованого псевдокоду до цього
репозиторію не додається.

## 1. Точні source pins

Linux source snapshot: [torvalds/linux f4585067150b85e33f60876149a6e742928da75e](https://github.com/torvalds/linux/tree/f4585067150b85e33f60876149a6e742928da75e).

| Файл | Blob SHA | Що підтверджено |
|---|---|---|
| nvkm/engine/gr/gp107.c | cc2bb0d0a9870e6145edef92babc480062e2d8c8 | GP107 GR firmware declarations і firmware interface v0 |
| nvkm/subdev/acr/gp102.c | 084f28449e527077b1fd1f29fc75cafd75d9c46e | спільні GP102 ACR loaders та GP107 path declarations |
| nvkm/subdev/acr/gm200.c | fd78965d841f9f632b2db8245f49868f22ec28f2 | WPR/LSB builder, signature record і FECS/GPCCS bootstrap |
| nvkm/engine/gr/gm200.c | b5210b31c1b2c2cdaa22b246517758b09d2bc534 | FECS → GPCCS → software GR loader; no-firmware fallback |
| nvkm/engine/gr/gk20a.c | 035ea213f543336923eb321b7673313314407765 | parser/loader для sw_ctx, sw_nonctx, sw_bundle_init, sw_method_init |
| nvkm/engine/device/base.c | a2ed8c4fe52a0bfcc7f48e4ff49b328a10eef41b | GP107 subdevice wiring: ACR, GR, FIFO і display окремими функціями |
| nvkm/engine/sec2/gp102.c | c64013d1050067bff133a3cd5a12a976744fd97d | спільний GP102 SEC2 і GP107 version-0/version-1 declarations |
| nvkm/subdev/fb/gp102.c | 534553c6480547cd4ffdc7578c59838741b1b588 | GP107 NVDEC scrubber declaration |

Firmware manifest: [NVIDIA/linux-firmware nvidia-staging](https://github.com/NVIDIA/linux-firmware/blob/nvidia-staging/WHENCE),
WHENCE blob 5da99f80b771d2be7af41628aaa3fdb717609b76,
repository head 2237b9924a5e77308fdf2f5850f84b78074d21fc.

Це source pins для карти, не твердження, що Kali kernel string
7.2.15+kali-amd64 побудований із цього самого commit. Поки окремий binary ↔
source ↔ patchset pairing не завершено, runtime-висновки з цих upstream-файлів
для встановленого модуля не робити.

## 2. GP107 firmware paths

### GR: FECS / GPCCS та software context

gp107_gr оголошує такі шляхи через MODULE_FIRMWARE:

| Firmware path | Manifest у WHENCE | Статус |
|---|---|---|
| nvidia/gp107/gr/fecs_bl.bin | File | SOURCE_CONFIRMED |
| nvidia/gp107/gr/fecs_inst.bin | File | SOURCE_CONFIRMED |
| nvidia/gp107/gr/fecs_data.bin | File | SOURCE_CONFIRMED |
| nvidia/gp107/gr/fecs_sig.bin | File | SOURCE_CONFIRMED |
| nvidia/gp107/gr/gpccs_bl.bin | File | SOURCE_CONFIRMED |
| nvidia/gp107/gr/gpccs_inst.bin | File | SOURCE_CONFIRMED |
| nvidia/gp107/gr/gpccs_data.bin | File | SOURCE_CONFIRMED |
| nvidia/gp107/gr/gpccs_sig.bin | File | SOURCE_CONFIRMED |
| nvidia/gp107/gr/sw_ctx.bin | File | SOURCE_CONFIRMED |
| nvidia/gp107/gr/sw_nonctx.bin | File | SOURCE_CONFIRMED |
| nvidia/gp107/gr/sw_bundle_init.bin | symlink → ../../gp102/gr/sw_bundle_init.bin | SOURCE_CONFIRMED |
| nvidia/gp107/gr/sw_method_init.bin | symlink → ../../gp102/gr/sw_method_init.bin | SOURCE_CONFIRMED |

У gp107_gr_fwif[] source ставить interface version 0 із gm200_gr_load,
gp107_gr, gm200_gr_fecs_acr та gm200_gr_gpccs_acr, а далі має gm200_gr_nofw
fallback. Це описує source-level loader policy, а не доводить, які саме файли
були запитані або завантажені на цільовій машині.

#### Loader semantics: що саме вимагає GR

Таблиця firmware paths вище — це лише інвентар. Pinned source також показує
послідовність споживання:

1. `nv137_chipset` названий `GP107`; він під'єднує
   `gp102_acr_new`, `gp107_gr_new`, `gp100_fifo_new` та
   `gp102_disp_new` як окремі subdevice functions. Це доводить роздільність
   dispatch/ініціалізації ACR, GR, FIFO та display у таблиці пристрою, але не
   доводить, що KMS гарантовано працює після відмови GR.
2. `gp107_gr_fwif[]` вибирає interface version `0` з
   `gm200_gr_load`, `gp107_gr`, `gm200_gr_fecs_acr` і
   `gm200_gr_gpccs_acr`. Наступний запис — fallback
   `gm200_gr_nofw`.
3. `gm200_gr_load` послідовно завантажує FECS bootloader, instruction,
   data і signature files; потім ті самі чотири компоненти GPCCS. Якщо будь-який
   з цих двох firmware load helper-ів повертає помилку, вона передається
   нагору. Лише після успішних FECS і GPCCS ставиться `gr->firmware = true`,
   після чого запускається `gk20a_gr_load_sw`.
4. `gk20a_gr_load_sw` окремо читає чотири software data files:
   `sw_nonctx`, `sw_ctx`, `sw_bundle_init`, `sw_method_init` і
   перетворює їх у таблиці ініціалізації context/bundle/method. Це не той самий
   етап, що завантаження FECS/GPCCS Falcon images.
5. `gm200_gr_nofw` друкує `firmware unavailable` і повертає
   `-ENODEV`. Отже в цьому GP107 GR interface немає успішного
   no-firmware GR fallback. Це source-level висновок про GR engine, а не
   твердження, що весь DRM device або display subdevice обов'язково
   відмовляє.

Практичний висновок: на рівні публічного Nouveau source GP107 GR
3D/compute path залежить від FECS/GPCCS та software GR files. Не можна
позначати Free GR/3D/compute як доступний лише тому, що ядро містить
`gp107_gr_new` або що PCI/KMS identity прочитана. Окремо лишаються package
closure, firmware provenance, request/load outcome та фізичний function test.

#### ACR/LSF boundary: що видно, а що ні

У `nv137_chipset` ACR реалізований через `gp102_acr_new`, а GR loader
передає `gm200_gr_fecs_acr` і `gm200_gr_gpccs_acr` до ACR/LSF helpers.
Публічний код показує такі речі:

- GP102 ACR load path створює `AcrLoad` із `acr/bl` +
  `acr/ucode_load`, а unload path — із `acr/unload_bl` +
  `acr/ucode_unload`. Для GP107 ці шляхи оголошені через symlink у
  WHENCE, як наведено в таблиці вище.
- ACR load setup готує region descriptor для WPR; GM200 ACR builder
  формує WPR/LSB records для Falcon firmware.
- LSB builder перевіряє, що signature file має очікуваний розмір, і копіює
  signature bytes у LSB record.
- `gm200_gr_gpccs_acr` має прапорець
  `NVKM_ACR_LSF_FORCE_PRIV_LOAD`; `gm200_gr_fecs_acr` його не має.

Не робити з цього сильніших тверджень, ніж дозволяє source: ці фрагменти
показують шлях підготовки ACR/LSF metadata та передачі підпису у WPR record.
Вони самі по собі не доводять повну апаратну перевірку конкретного підпису,
можливість створити сумісний replacement без ключів NVIDIA або поведінку
конкретної карти під час boot. Ці питання позначаються `UNKNOWN`, доки немає
окремого публічного специфікаційного чи дозволеного runtime свідка.

#### Межа display/KMS

GP107 device table прив'язує `disp` до `gp102_disp_new`, окремо від
`gr` → `gp107_gr_new`. Це корисне архітектурне розділення, але воно не є
тестом. Статус `KMS_WITH_GR_FIRMWARE_ABSENT` лишається
`NOT_TESTED_H170`: не перетворювати `gm200_gr_nofw = -ENODEV` на
твердження, що display точно працює або точно не працює без GR firmware.
Для цього потрібен окремий, owner-approved фізичний display test на H170.

### ACR

GP107 ACR paths у спільному gp102.c:

| Firmware path | Manifest у WHENCE | Статус |
|---|---|---|
| nvidia/gp107/acr/bl.bin | symlink → ../../gp102/acr/bl.bin | SOURCE_CONFIRMED |
| nvidia/gp107/acr/ucode_load.bin | symlink → ../../gp102/acr/ucode_load.bin | SOURCE_CONFIRMED |
| nvidia/gp107/acr/unload_bl.bin | symlink → ../../gp102/acr/unload_bl.bin | SOURCE_CONFIRMED |
| nvidia/gp107/acr/ucode_unload.bin | symlink → ../../gp102/acr/ucode_unload.bin | SOURCE_CONFIRMED |

Loader source використовує пари acr/bl + acr/ucode_load та
acr/unload_bl + acr/ucode_unload. Фактичний runtime request/успішне
завантаження на GP107 тут не вимірювали.

### SEC2

Спільний gp102_sec2 оголошує два набори кандидатів:

| Version family | Firmware paths | Manifest у WHENCE |
|---|---|---|
| SEC2 v0 | nvidia/gp107/sec2/desc.bin, image.bin, sig.bin | усі symlink → відповідні GP102 файли |
| SEC2 v1 | nvidia/gp107/sec2/desc-1.bin, image-1.bin, sig-1.bin | усі symlink → відповідні GP102 файли |

У source firmware interface перелічений у порядку v1, v0, потім no-firmware
fallback. Це перелік підтриманих source candidates; без точного runtime log і
binary pairing не стверджувати, який варіант вибрав конкретний boot.

### NVDEC scrubber

gp102_fb.c оголошує nvidia/gp107/nvdec/scrubber.bin; WHENCE позначає його як
symlink на ../../gp102/nvdec/scrubber.bin. У gp102_fb_oneinit() створюється
firmware-backed scrubber object для NVDEC. Ця декларація не доводить, що
VPR scrubber був активований на тестовій машині або є необхідною умовою
звичайного GR compute dispatch.

### GSP

У межах наведених GP107-specific declarations немає окремого
nvidia/gp107/gsp/* шляху. Не переносити на Pascal висновки про GSP firmware
інших GPU поколінь і не робити GSP/Reclocking частиною цього спринту.

## 3. Ліцензійна межа

NVIDIA/linux-firmware WHENCE групує наведені записи під
Driver: nouveau - NVIDIA GPU driver; наприкінці цієї групи вказано:
Licence: Redistributable. See LICENCE.nvidia for details.

LICENCE.nvidia містить Open Source Exception: копіювання й розповсюдження
бінарних файлів дозволене лише для використання з операційними системами під
OSI-approved open-source license, за умови, що firmware binaries не змінені,
а копія цієї ліцензії передається разом із ними. Там же є обмеження щодо
reverse engineering, translation та використання програмного забезпечення.
Це фіксація тексту опублікованої ліцензії, не юридичний висновок про кожну
можливу конфігурацію дистрибуції.

Практичні наслідки для WSM:

1. **Free profile не включає NVIDIA proprietary firmware.** Не копіювати ці
   файли до wsm-desktop, Guix channel, ISO або source repository. Вільність
   Nouveau driver не перетворює firmware blobs на вільний код.
2. **Compatibility — окрема opt-in межа.** Будь-який майбутній firmware package
   потребує окремої перевірки точних upstream files, symlink closure, незмінності
   бінарних файлів, наявності повної LICENCE.nvidia та відповідності умовам
   конкретного способу розповсюдження.
3. **Не перевидавати blobs у цьому дослідницькому репозиторії.** Достатньо
   публічних шляхів, посилань, hashes власних текстових manifests і runtime
   inventory. Немає підстав додавати vendor binary або RE output.
4. WSM package metadata issue #367 щодо власного wsm-tools — окреме питання;
   його не можна вважати вирішеним цим firmware audit.

Джерела ліцензії: [NVIDIA/linux-firmware LICENCE.nvidia](https://github.com/NVIDIA/linux-firmware/blob/nvidia-staging/LICENCE.nvidia)
та [WHENCE](https://github.com/NVIDIA/linux-firmware/blob/nvidia-staging/WHENCE).

## 4. Що робити далі — мінімальний read-only gate

Поточна цінність наступного кроку — provenance, а не новий workload чи глибша
декомпіляція.

1. На окремому Kali witness host зафіксувати uname -r, modinfo -n nouveau,
   modinfo -F vermagic nouveau, modinfo -F firmware nouveau,
   dpkg-query -S "$(modinfo -n nouveau)", binary/source package versions,
   readelf -n Build ID та SHA-256 модуля.
2. Пінити точний Kali source package/commit і його patch set. Перевірити
   nonstall_ctor, runl->id та index_nr у цьому exact source. Якщо pairing
   не доведено — KERNEL_SOURCE_PAIRING=UNVERIFIED.
3. Після pairing зіставити modinfo -F firmware nouveau і boot journal із
   локальними firmware paths та symlink targets. Відсутній log рядок не є доказом,
   що файл ніколи не запитувався; зберігати окремо declaration, request і load
   outcome.
4. Жодних нових Vulkan enumeration/submit, compute workload, probe attach,
   kprobe/ftrace/BPF, driver unbind/switch, firmware install, BAR/MMIO, VBIOS,
   reboot або BIOS operations у цьому завданні.

Повторна декомпіляція R580 UVM/RM, broad /r, full Ghidra та спроби
reclocking не є наступним пріоритетом: вони не закривають ні Free profile, ні
source pairing, ні конкретний user-channel → runlist → NONSTALL event gap.
