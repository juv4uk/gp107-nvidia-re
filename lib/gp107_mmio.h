#ifndef GP107_MMIO_H
#define GP107_MMIO_H

#include <stddef.h>
#include <stdint.h>

#include "gp107_identity.h"

/*
 * Physical MMIO is NOT AUTHORIZED / NOT RUN. The public API always returns
 * GP107_ERR_NOT_AUTHORIZED; no CLI flag can grant hardware access.
 * This interface remains only as a stable fail-closed boundary.
 */

int gp107_mmio_read32(const char *sysfs_root, const char *expect_bdf,
                      int allow, uint32_t offset, uint32_t *value,
                      char *err, size_t errsz);

#endif
