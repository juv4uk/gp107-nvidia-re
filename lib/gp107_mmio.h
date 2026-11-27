#ifndef GP107_MMIO_H
#define GP107_MMIO_H

#include <stddef.h>
#include <stdint.h>

#include "gp107_identity.h"

/*
 * Optional read-only aperture seam. The implementation is software-only
 * research code; no physical MMIO, driver unbind or alternate boot has been
 * authorized. The public operation enforces its own opt-in, inventory,
 * driver-binding and BAR-size gates; a caller cannot bypass them by invoking
 * this API directly.
 *
 * No write mapping, no RM requests, no FIFO, no doorbell, no firmware,
 * no BOOT0 constant and no register name is encoded here.
 */

#define GP107_MMIO_WINDOW 4096u

/* All gates are enforced inside this public operation. */
int gp107_mmio_read32(const char *sysfs_root, const char *expect_bdf,
                      int allow, uint32_t offset, uint32_t *value,
                      char *err, size_t errsz);

#endif
