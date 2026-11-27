.PHONY: all test gate-root test-root clean

all:
	$(MAKE) -C probes
	$(MAKE) -C pascal

test:
	bash scripts/test-pascal-probe.sh

# Опційний root-свідок. Не входить до `test`: базовий гейт лишається
# детермінованим і не потребує sudo. За потреби: SUDO_FLAGS=-S.
gate-root test-root:
	bash scripts/test-root-witness.sh

clean:
	$(MAKE) -C probes clean || true
	$(MAKE) -C pascal clean || true
