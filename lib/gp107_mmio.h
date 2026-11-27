#ifndef GP107_MMIO_H
#define GP107_MMIO_H

#include <stddef.h>
#include <stdint.h>

#include "gp107_identity.h"

/*
 * Optional read-only aperture seam. Owner-authorized in the session that
 * created this slice, but deliberately inert unless the caller passes an
 * explicit opt-in flag AND no kernel driver is bound to the device.
 *
 * No write mapping, no RM requests, no FIFO, no doorbell, no firmware,
 * no BOOT0 constant and no register name is encoded here.
 */

#define GP107_MMIO_WINDOW 4096u

int gp107_mmio_require_optin(int allow, char *err, size_t errsz);

int gp107_mmio_check_driver(const struct gp107_inventory *inv,
                            char *err, size_t errsz);

/* Enforces opt-in, fresh BDF/driver inventory, alignment and resource
 * bounds internally; callers cannot bypass the policy via this API. */
int gp107_mmio_read32(const char *sysfs_root, const char *bdf, int allow_mmio,
                      uint32_t offset, uint32_t *value,
                      char *err, size_t errsz);

#endif
