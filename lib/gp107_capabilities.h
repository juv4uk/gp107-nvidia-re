#ifndef GP107_CAPABILITIES_H
#define GP107_CAPABILITIES_H

#include <stddef.h>

#include "gp107_identity.h"

/*
 * Machine-readable projection of what this slice may actually do.
 * This is research code, not a runtime capability word and not an ABI.
 * It never upgrades a sysfs inventory fact into a register right.
 */
int gp107_capability_report(const struct gp107_inventory *inv,
                            int allow_mmio, char *out, size_t cap);

#endif
