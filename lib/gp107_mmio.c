#include "gp107_mmio.h"

 /*
  * Physical MMIO is not authorized in this research profile.
  * This API intentionally has no device-file open, mapping, or register-read
  * implementation. A command-line flag is not owner authorization.
  */

int gp107_mmio_read32(const char *sysfs_root, const char *expect_bdf,
                      int allow, uint32_t offset, uint32_t *value,
                      char *err, size_t errsz)
{
    if (err == NULL || errsz == 0) {
        return GP107_ERR_USAGE;
    }
    err[0] = '\0';
    if (sysfs_root == NULL || expect_bdf == NULL || value == NULL) {
        return gp107_set_error(err, errsz,
                               "MMIO-FAIL step=bad-argument code=%d",
                               GP107_ERR_USAGE);
    }

    (void)allow;
    (void)offset;
    return gp107_set_error(err, errsz,
                           "MMIO-FAIL step=owner-authorization-required code=%d",
                           GP107_ERR_NOT_AUTHORIZED);
}
