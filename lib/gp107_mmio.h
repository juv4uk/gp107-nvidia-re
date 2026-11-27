#ifndef GP107_MMIO_H
#define GP107_MMIO_H

#include <stddef.h>
#include <stdint.h>

#include "gp107_identity.h"

//*
 * Optional read-only aperture seam. Software-gated research code only:
 * no physical MMIO, driver unbind or alternate boot is authorized.
 * The public function enforces opt-in, identity, binding and BAR-size checks
 * itself; direct C callers cannot bypass the gates through a lower-level API.
 *
 * This API's allow flag is not owner authorization.
 */
 
#define GP107_MMIO_WINDOW 4096u

int gp107_mmio_read32(const char *sysfs_root, const char *expect_bdf,
                      int allow, uint32_t offset, uint32_t *value,
                      char *err, size_t errsz);

#endif
