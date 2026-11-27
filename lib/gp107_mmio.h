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

/* x86-64 only: one volatile 32-bit load with a following load fence.
 * Declared here so the C/assembly equivalence gate can compare paths. */
uint32_t gp107_mmio_load32_asm(const volatile void *addr);

int gp107_mmio_require_optin(int allow, char *err, size_t errsz);

int gp107_mmio_check_driver(const struct gp107_inventory *inv,
                            char *err, size_t errsz);

/* The public operation enforces opt-in, inventory identity and driver
 * binding itself; callers cannot bypass the gates by skipping CLI checks. */
int gp107_mmio_read32(const char *sysfs_root, const char *expect_bdf,
                      uint32_t offset, int allow,
                      uint32_t *value, char *err, size_t errsz);

#endif
