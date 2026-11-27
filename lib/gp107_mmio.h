#ifndef GP107_MMIO_H
#define GP107_MMIO_H

#include <stddef.h>
#include <stdint.h>

#include "gp107_identity.h"

/*
 * Deliberately deferred MMIO API.
 *
 * The API validates caller intent, exact PCI identity, driver binding,
 * BAR0 type/size and offset bounds, then stops with
 * GP107_ERR_SAFE_OFFSET_UNPROVEN. It does not open resource0, map BAR0,
 * dereference an aperture, or grant physical MMIO permission.
 *
 * --allow-mmio is a software acknowledgement only, never owner approval.
 */

#define GP107_MMIO_WINDOW 4096u

int gp107_mmio_read32(const char *sysfs_root, const char *expect_bdf,
                      int allow, uint32_t offset, uint32_t *value,
                      char *err, size_t errsz);

#endif
