# 38 — GP107: карта Nouveau firmware dependencies та межа Free/Compatibility

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
