#ifndef GP107_MMIO_H
#define GP107_MMIO_H

#include <stddef.h>
#include <stdint.h>

#include "gp107_identity.h"

/*
 * Optional read-only aperture seam. This code is not owner authorization.
 * Physical use still requires explicit owner approval and a documented
 * read-safe register. The explicit flag is a software gate only.
 *
 * No write mapping, no RM requests, no FIFO, no doorbell, no firmware,
 * no BOOT0 constant and no register name is encoded here.
 */

#define GP107_MMIO_WINDOW 4096u

/* x86-64 only: one volatile 32-bit load with a following load fence. */
uint32_t gp107_mmio_load32_asm(const volatile void *addr);

int gp107_mmio_require_optin(int allow, char *err, size_t errsz);

int gp107_mmio_check_driver(const struct gp107_inventory *inv,
                            char *err, size_t errsz);

int gp107_mmio_read32(const char *sysfs_root, const char *bdf, int allow_mmio,
                      uint32_t offset, uint32_t *value,
                      char *err, size_t errsz);

#endif
