#!/usr/bin/env bash
# open-driver capability gate — адитивний research- ledger для відкритого boot.
#
# Не є ABI-авторитетом і не змінює pin-и. Не запускає драйвер, PR #21,
# MMIO-запити чи nvidia-settings. Лише перевіряє вже здобуті артефакти
# і друкує S-вираз із явно позначеними станами доказів.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# Непідмінні джерела для генерації мутаційних негативів.
SRC_VULK=$ROOT/evidence/nouveau-20261127/09-vulkaninfo.txt
SRC_LSPCI=$ROOT/evidence/nouveau-20261127/02-lspci.txt
SRC_DOC14=$ROOT/docs/14-nvk-vector-add-compute-result.md

WORK=$(mktemp -d)
trap '_rc=$?; rm -rf "$WORK"; if [ "$_rc" -ne 0 ]; then
         echo "OPEN-DRIVER-GATE-FAIL крок=\"$BASH_COMMAND\" код=$_rc" >&2
       fi' EXIT

fail() { echo "OPEN-DRIVER-GATE-FAIL: $*" >&2; exit 1; }
step() { printf '== %s\n' "$*"; }

need() { grep -Fq -- "$1" "$2" || fail "нема маркера '$1' у $3"; }

check_all() {
  # Шляхи перевизначаються всередині виклику — мутаційні негативи підміняють
  # *_LOG у дочірній оболонці й мають справді перевіряти підмінені файли.
  local CMD=${CMD_LOG:-$ROOT/evidence/nouveau-20261127/01-cmdline.txt}
  local LSPCI=${LSPCI_LOG:-$ROOT/evidence/nouveau-20261127/02-lspci.txt}
  local LSMOD=${LSMOD_LOG:-$ROOT/evidence/nouveau-20261127/03-lsmod.txt}
  local KLOG=${KLOG_LOG:-$ROOT/evidence/nouveau-20261127/04-kernel-log.txt}
  local VULK=${VULK_LOG:-$ROOT/evidence/nouveau-20261127/09-vulkaninfo.txt}
  local EXEC=${EXEC_LOG:-$ROOT/experiments/nvk-compute-smoke/artifacts-v4/08-dispatch-ioctl.txt}
  local DOC14=${DOC14_LOG:-$ROOT/docs/14-nvk-vector-add-compute-result.md}
  local DOC15=${DOC15_LOG:-$ROOT/docs/15-rea-static-markers-nonstall-runlist-event.md}
  local DOC16=${DOC16_LOG:-$ROOT/docs/16-nvidia-settings-autostart-open-driver-fix.md}

  step 'firewall research-межі'
  bash "$ROOT/scripts/check-no-driver-overreach.sh"

  step 'ABI authority boundary'
  # Шукаємо саме authoritative pin-ФАЙЛ, а не рядок-детектор у самих gate-скриптах.
  if git ls-files | grep -E '(^|/)(target-abi-pin\.lisp|wsm-target-contract)' >/dev/null; then
    fail 'research-репо відстежує authoritative ABI-pin'
  fi
  echo 'ABI-BOUNDARY-OK pin-file=absent documented-provenance=allowed'

  step 'наявність сирих свідків'
  for f in "$CMD" "$LSPCI" "$LSMOD" "$KLOG" "$VULK" "$EXEC" "$DOC14" "$DOC15" "$DOC16"; do
    [ -r "$f" ] || fail "свідок недоступний: $f"
  done

  step 'cmdline: відкритий boot'
  need 'wsm_open_driver=1' "$CMD" 'cmdline'
  need 'modprobe.blacklist=nvidia' "$CMD" 'cmdline'
  need 'nouveau.debug=TOP=trace,FIFO=debug' "$CMD" 'cmdline'

  step "PCI identity + зв'язування з nouveau"
  need '0000:01:00.0' "$LSPCI" 'lspci'
  need '[10de:1c82]' "$LSPCI" 'lspci'
  need 'Kernel driver in use: nouveau' "$LSPCI" 'lspci'
  if grep -Fq 'Kernel driver in use: nvidia' "$LSPCI"; then
    fail "GPU прив'язано до nvidia, а не nouveau"
  fi

  step 'нема активного пропрієтарного модуля'
  if awk '$1 ~ /^nvidia/ { print }' "$LSMOD" | grep -q .; then
    fail 'lsmod показує активний nvidia*'
  fi
  need 'nouveau' "$LSMOD" 'lsmod'

  step 'Vulkan ICD: NVK, а не пропрієтарний/CPU'
  need 'driverID           = DRIVER_ID_MESA_NVK' "$VULK" 'vulkaninfo'
  need 'driverName         = NVK' "$VULK" 'vulkaninfo'
  need 'vendorID           = 0x10de' "$VULK" 'vulkaninfo'
  need 'deviceID           = 0x1c82' "$VULK" 'vulkaninfo'
  need 'NVIDIA GeForce GTX 1050 Ti (NVK GP107)' "$VULK" 'vulkaninfo'
  if grep -Eiq 'llvmpipe|softpipe|DRIVER_ID_NVIDIA_PROPRIETARY' "$VULK"; then
    fail ' ICD не є чистим NVK'
  fi

  step 'kernel log: GP107 string-only, без BOOT0-вичитки'
  need 'NVIDIA GP107 (137000a1)' "$KLOG" 'kernel log'
  if grep -Eiq 'BOOT0[^[:space:]]*[[:space:]]*(read|value)' "$KLOG"; then
    fail ' log стверджує BOOT0-вичитку'
  fi

  step 'trace submit: DRM_NOUVEAU_EXEC + SYNCOBJ_WAIT'
  need 'DRM_IOCTL_NOUVEAU_EXEC' "$EXEC" 'ioctl trace'
  need 'DRM_IOCTL_SYNCOBJ_WAIT' "$EXEC" 'ioctl trace'
  [ "$(grep -Fc 'DRM_IOCTL_NOUVEAU_EXEC' "$EXEC")" -ge 1 ] \
    || fail 'нема жодного EXEC'

  step 'compute witness: PASS тільки з commited-артефактів'
  need 'PHYSICAL_COMPUTE_TEST=PASS' "$DOC14" 'doc 14'
  need 'NVK-COMPUTE-SMOKE-OK bdf=0000:01:00.0' "$DOC14" 'doc 14'
  need 'fence=SIGNALED' "$DOC14" 'doc 14'
  need 'match=yes' "$DOC14" 'doc 14'
  need 'pr21=NOT-RUN' "$DOC14" 'doc 14'
  need 'mmio=none' "$DOC14" 'doc 14'

  step 'відкриті питання лишаються відкритими'
  grep -Eq 'NONSTALL_EVENT_SUBSCRIPTION_OBSERVED.*UNPROVEN' "$DOC15" \
    || fail 'nonstall не позначено UNPROVEN'
  grep -Eq 'CHANNEL_RUNLIST_CORRELATED.*UNPROVEN' "$DOC15" \
    || fail 'channel→runlist не позначено UNPROVEN'
  grep -Eq 'BOOT0.*UNPROVEN' "$DOC15" \
    || fail 'BOOT0 не позначено UNPROVEN'

  step 'autostart фікс присутній'
  need 'ConditionKernelCommandLine=!wsm_open_driver=1' "$DOC16" 'doc 16'
  need 'ConditionResult=no' "$DOC16" 'doc 16'
}

# --- Основний прохід -------------------------------------------------------
check_all

# --- Негативні свідки: gate не вакуальний ----------------------------------
step 'negative witness (пропрієтарний ICD відхилено)'
sed 's/DRIVER_ID_MESA_NVK/DRIVER_ID_NVIDIA_PROPRIETARY/' "$SRC_VULK" >"$WORK/bad-vulk.txt"
if ( export VULK_LOG="$WORK/bad-vulk.txt"; check_all ) >/dev/null 2>"$WORK/neg-vulk.err"; then
  fail ' gate прийняв пропрієтарний ICD'
fi
grep -Fq 'OPEN-DRIVER-GATE-FAIL:' "$WORK/neg-vulk.err" \
  || fail 'нема названого negative-маркера для ICD'

step 'negative witness (nvidia binding відхилено)'
sed 's/Kernel driver in use: nouveau/Kernel driver in use: nvidia/' "$SRC_LSPCI" >"$WORK/bad-lspci.txt"
if ( export LSPCI_LOG="$WORK/bad-lspci.txt"; check_all ) >/dev/null 2>"$WORK/neg-bind.err"; then
  fail " gate прийняв GPU, прив'язаний до nvidia"
fi
grep -Fq 'OPEN-DRIVER-GATE-FAIL:' "$WORK/neg-bind.err" \
  || fail 'нема названого negative-маркера для binding'

step 'negative witness (NOT_RUN compute відхилено)'
sed 's/PHYSICAL_COMPUTE_TEST=PASS/PHYSICAL_COMPUTE_TEST=NOT_RUN/' "$SRC_DOC14" >"$WORK/bad-doc14.txt"
if ( export DOC14_LOG="$WORK/bad-doc14.txt"; check_all ) >/dev/null 2>"$WORK/neg-compute.err"; then
  fail ' gate прийняв compute NOT_RUN'
fi
grep -Fq 'OPEN-DRIVER-GATE-FAIL:' "$WORK/neg-compute.err" \
  || fail 'нема названого negative-маркера для compute'

# --- Research-контракт -----------------------------------------------------
cat <<'CONTRACT'
((kind . wsm-open-driver-capability-research)
 (authority . gp107-nvidia-re-research-not-abi)
 (abi-pin . untouched)
 (host
  (vendor . 0x10de) (device . 0x1c82) (bdf . "0000:01:00.0")
  (driver-binding . nouveau) (evidence . runtime-proven))
 (vulkan
  (driver-id . DRIVER_ID_MESA_NVK) (driver-name . NVK)
  (evidence . runtime-proven))
 (compute
  (vector-add . pass) (fence . signaled) (checksum . verified)
  (pr21-executable . not-run) (mmio . none)
  (evidence . runtime-proven-from-committed-artifacts))
 (boot0 (value . absent) (evidence . unproven))
 (nonstall-event-subscription (evidence . unproven))
 (channel-runlist-correlation (evidence . unproven))
 (mmio (right . none) (provisioning . deferred))
 (transitions
  ((pci-config -> nouveau-vulkan) . allowed-inventory-plus-driver-id)
  ((vulkan-id -> mmio) . forbidden))
 (bounds (human-attestation . none) (tested-by . none) (abi-authority . none)))
CONTRACT

echo "OPEN-DRIVER-GATE-OK fpc=unrequired abi-pin=untouched boot0=unproven mmio=none pr21=NOT-RUN negative=3"
