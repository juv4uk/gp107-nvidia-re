#ifndef GP107_MMIO_H
#define GP107_MMIO_H

#include <stddef.h>
#include <stdint.h>

#include "gp107_identity.h"

/*
 * Optional read-only aperture seam. Software-gated research code only:
 * physical MMIO, driver unbind and alternate boot are not authorized.
 * The sole public operation enforces opt-in, PCI identity, binding, BAR-space,
 * BAR-size and offset checks internally. Its allow flag is not owner approval.
 *
 * No write mapping, RM requests, FIFO, doorbell, firmware or BOOT0 value.
 */

#define GP107_MMIO_WINDOW 4096u

/* The public operation enforces opt-in, inventory identity and driver
 * binding itself; callers cannot bypass the gates by skipping CLI checks. */
int gp107_mmio_read32(const char *sysfs_root, const char *expect_bdf,
                      uint32_t offset, int allow,
                      uint32_t *value, char *err, size_t errsz);

#endif
