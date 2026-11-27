#ifndef GP107_MMIO_H
#define GP107_MMIO_H

#include <stddef.h>
#include <stdint.h>

#include "gp107_identity.h"

/*
 * Optional MMIO research seam. The CLI flag is not owner authorization.
 * No BAR0 register has a proven read-safe contract, so the public API fails
 * closed after identity checks and performs no aperture mapping.
 *
 * No write mapping, no RM requests, no FIFO, no doorbell, no firmware,
 * no BOOT0 constant and no register name is encoded here.
 */

#define GP107_MMIO_WINDOW 4096u

/* Isolated x86-64 leaf, retained for static inspection only; not called here. */
uint32_t gp107_mmio_load32_asm(const volatile void *addr);

int gp107_mmio_require_optin(int allow, char *err, size_t errsz);

int gp107_mmio_check_driver(const struct gp107_inventory *inv,
                            char *err, size_t errsz);

/* Enforces explicit opt-in and fresh inventory internally; currently defers. */
int gp107_mmio_read32(const char *sysfs_root, const char *bdf, int allow_mmio,
                      uint32_t offset, uint32_t *value,
                      char *err, size_t errsz);

#endif
