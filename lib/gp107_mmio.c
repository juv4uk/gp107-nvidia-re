#include "gp107_mmio.h"

/*
 * Physical MMIO is intentionally unavailable in this revision.
 *
 * A command-line opt-in flag is not owner authorization, and a userspace
 * caller must not be able to turn sysfs inventory into an aperture mapping.
 * Keep the API as a named, fail-closed boundary until a separately reviewed
 * owner-approved design supplies a proven-safe register allowlist.
 */

int gp107_mmio_require_optin(int allow, char *err, size_t errsz)
{
    (void)allow;
    return gp107_set_error(err, errsz,
                           "MMIO-FAIL step=owner-authorization-required code=%d",
                           GP107_ERR_NOT_AUTHORIZED);
}

int gp107_mmio_check_driver(const struct gp107_inventory *inv,
                            char *err, size_t errsz)
{
    if (inv == NULL) {
        return gp107_set_error(err, errsz,
                               "MMIO-FAIL step=bad-argument code=%d",
                               GP107_ERR_USAGE);
    }
    if (inv->driver.bound) {
        return gp107_set_error(err, errsz,
                               "MMIO-FAIL step=driver-bound code=%d driver=%s",
                               GP107_ERR_DRIVER_BOUND, inv->driver.name);
    }
    return GP107_OK;
}

int gp107_mmio_read32(const char *sysfs_root, const char *bdf,
                      uint32_t offset, uint32_t *value,
                      char *err, size_t errsz)
{
    /*
     * Deliberately do not inspect paths, open resource0, mmap, or dereference
     * the supplied address. This entry point denies even a direct API caller.
     */
    (void)sysfs_root;
    (void)bdf;
    (void)offset;
    (void)value;
    return gp107_set_error(err, errsz,
                           "MMIO-FAIL step=physical-mmio-not-authorized code=%d",
                           GP107_ERR_NOT_AUTHORIZED);
}
