.PHONY: all test test-valid-cards-static test-capability-driver gate-root test-root clean

all:
	$(MAKE) -C probes
	$(MAKE) -C pascal
	$(MAKE) -C lib

test:
	bash scripts/test-pascal-probe.sh
	bash scripts/check-no-driver-overreach.sh
	bash scripts/test-evidence-manifest.sh
	python3 -m unittest tests.test_decode_ioctl
	bash scripts/test-gp107-matrix-collector.sh

# Додатковий C11-гейт: не змінює базовий Pascal-гейт і не торкається заліза
# поза read-only sysfs inventory.
test-capability-driver:
	$(MAKE) -C lib test

# Host-independent source guard: no FPC, GPU discovery or RM ioctl.
test-valid-cards-static:
	PASCAL_PROBE_STATIC_ONLY=1 bash scripts/test-pascal-probe.sh

# Опційний root-свідок. Не входить до `test`: базовий гейт лишається
# детермінованим і не потребує sudo. За потреби: SUDO_FLAGS=-S.
gate-root test-root:
	bash scripts/test-root-witness.sh

clean:
	$(MAKE) -C probes clean || true
	$(MAKE) -C pascal clean || true
	$(MAKE) -C lib clean || true
