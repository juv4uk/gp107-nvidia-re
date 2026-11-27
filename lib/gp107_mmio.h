#ifndef GP107_MMIO_H
#define GP107_MMIO_H

#include <stddef.h>
#include <stdint.h>

#include "gp107_identity.h"

/*
 * Physical MMIO is NOT AUTHORIZED / NOT RUN. This module is a fail-closed
 * API boundary only: --allow-mmio is not owner authorization, and no public
 * function in this module opens or maps PCI resource0.
 *
 * The API is intentionally kept so direct callers receive a stable denial.
 */

int gp107_mmio_require_optin(int allow, char *err, size_t errsz);

int gp107_mmio_check_driver(const struct gp107_inventory *inv,
                            char *err, size_t errsz);

int gp107_mmio_read32(const char *sysfs_root, const char *bdf,
                      uint32_t offset, uint32_t *value,
                      char *err, size_t errsz);

#endif
