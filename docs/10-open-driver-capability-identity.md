# 10 — Відкритий драйвер лісп-машини: перший зріз capability identity

Це **research-контракт**, а не ABI й не драйвер. Він не змінює SENS, CML,
`wsm-os-lisp`, `wsm-target-contract`, ADR, target contract чи ABI-pin v8
(`b5ec3211…`). Мета — перетворити вже здобуті GP107-свідки у виконувану
межу, з якої можна ростити відкритий драйвер лісп-машини, не підміняючи
інвентарний факт правом доступу.

Стиль запозичено з [`wsm-lazarus`](https://github.com/juv4uk/wsm-lazarus):
Pascal обчислює й відмовляє, shell називає кожен крок, firewall дивиться
на код після зрізу коментарів, а негативні мутації доводять, що gate не
вакуальний.

## 1. Чому саме identity

Відкритий драйвер тут — не «замінити `nvidia.ko`», а capability-ланцюжок у
лісп-машині:

```text
PciConfig (інвентар) → RmControl (ідентичність) → Mmio (володіння) →
GPFIFO/channel (черга) → fence/IRQ (синхронізація) → framebuffer/compute
```

ADR-007 `wsm-os-lisp` уже ратифікував heads:

- `PciConfig` ≠ `Mmio`; BAR-адреса не дає права мапіти апертуру;
- у hosted Linux під активним `nvidia.ko` `BOOT0 = UNPROVEN` нормативний;
- легальний hosted-шлях ідентифікації — `PciConfig + RmControl` (локальний D7);
- `0x137000A1` лишається `string-only`.

Тому перший зріз не чіпає MMIO: він фіксує, **що вже доведено**, і явно
забороняє перехід до того, що не доведено.

## 2. Форма контракту

Еміттер `pascal/04_capability_identity.pas` читає лог звичайного
`scripts/test-pascal-probe.sh` і друкує S-вираз:

| Поле | Значення з реального логу | Стан |
|---|---|---|
| `pci-config.vendor/device` | `0x10de / 0x1c82` | `runtime-proven` |
| `pci-config.bdf` | `0000:01:00.0` | `runtime-proven` |
| `pci-config.bar0-base` | `0xee000000` | `runtime-proven` |
| `pci-config.right` | `inventory-only`, `mmio-right = none` | design boundary |
| `rm-control.arch/impl/rev/subrev` | `0x130 / 0x7 / 0xa1 / 0x2` | `runtime-proven` |
| `rm-control.gpu-id/minor` | `0x100 / 0` | `runtime-proven` |
| `rm-control.device-id` | `0`, **не** PCI `0x1c82` | `runtime-proven` + `interpretation` |
| `rm-control.valid-cards` | `1`, мутаційний gate | `runtime-proven` на цій платі |
| `mmio.boot0` | `unproven` | `UNPROVEN` нормативно |
| `mmio.resource0-open` | `EACCES` | `runtime-proven negative` |

Переходи:

- `pci-config → rm-control` — дозволений лише коли рівно одна картка;
- `rm-control → mmio` — **заборонений у hosted Linux**;
- `mmio` на bare-metal/UEFI — окремий seam, `deferred`, тут не відкривається.

## 3. Що перевіряє gate

`bash scripts/test-capability-identity.sh`:

1. `check-no-driver-overreach.sh` — у коді заборонені `PROT_WRITE`, `MAP_FIXED`,
   `O_RDWR`, `FpWrite`, `pwrite`, `nva`, literals BOOT0 і `Tested-by`.
2. У research-репо немає authoritative `target-abi-pin.lisp`.
3. FPC 3.2.2 pin, static ELF без libc (`-XS`).
4. Eміттер відмовляє, якщо немає маркерів, є друга GPU або `ambiguous valid_cards=`.
5. Два мутаційні негативи: видалення `BOOT0: UNPROVEN` → `IDENTITY-FAIL step=missing-line`;
   додавання другої GPU → `IDENTITY-FAIL step=card-count code=12`.
6. У виході немає `137000A1`, `Tested-by`, `PROT_WRITE`.

Можна перевірити збережений лог без повторного доступу до заліза:

```bash
GATE_LOG=/tmp/opencode/valid-cards-gate2.log \
  bash scripts/test-capability-identity.sh
```

Без `GATE_LOG` сценарій сам викликає `test-pascal-probe.sh` і працює
непривілейовано: `resource0` дає `EACCES`, BOOT0 лишається `UNPROVEN`.

## 4. Межі

- Це не є Lisp-викликом і не capability word у runtime: S-вираз є
  **людиночитаною проєкцією свідка**, поки не зроблено owner-рішення про ABI.
- `runtime-proven` тут означає «значення прочитане власним зондом у лозі»,
  а не «драйвер працює на цій платі».
- Жодного dispatch, pushbuffer, GPFIFO, doorbell, ALLOW/BLOCK чи GPU- work.
- Жодного `Tested-by`, release/tag чи transfer.
- Наступний зріз (`GPFIFO channel`) не починати до #18 trace witness і явної
  owner-санкції на фізичний запуск.

## Українською одном реченням

Спершу фіксуємо, що лісп-машина вже може **перевірено знати** про GP107, і
забороняємо собі видавати це знання за право писати в апаратуру.
