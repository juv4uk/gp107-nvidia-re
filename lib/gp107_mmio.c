#include "gp107_mmio.h"

int gp107_mmio_require_optin(int allow, char *err, size_t errsz)
{
    if (!allow) return gp107_set_error(err, errsz,
                                       "MMIO-FAIL step=opt-in-required code=%d",
                                       GP107_ERR_OPTIN);
    return GP107_OK;
}

int gp107_mmio_check_driver(const struct gp107_inventory *inv,
                            char *err, size_t errsz)
{
    if (inv == NULL) return gp107_set_error(err, errsz,
                                            "MMIO-FAIL step=bad-argument code=%d",
                                            GP107_ERR_USAGE);
    if (inv->driver.bound) return gp107_set_error(err, errsz,
                                                  "MMIO-FAIL step=driver-bound code=%d driver=%s",
                                                  GP107_ERR_DRIVER_BOUND, inv->driver.name);
    return GP107_OK;
}

int gp107_mmio_read32(const char *sysfs_root, const char *bdf, int allow_mmio,
                      uint32_t offset, uint32_t *value,
                      char *err, size_t errsz)
{
    struct gp107_inventory inv;
    int rc;

    if (sysfs_root == NULL || bdf == NULL || value == NULL || err == NULL || errsz == 0)
        return gp107_set_error(err, errsz, "MMIO-FAIL step=bad-argument code=%d", GP107_ERR_USAGE);

    rc = gp107_mmio_require_optin(allow_mmio, err, errsz);
    if (rc != GP107_OK) return rc;
    rc = gp107_inventory_scan(sysfs_root, bdf, &inv, err, errsz);
    if (rc != GP107_OK) return rc;
    rc = gp107_mmio_check_driver(&inv, err, errsz);
    if (rc != GP107_OK) return rc;

    if ((offset & 3u) != 0)
        return gp107_set_error(err, errsz, "MMIO-FAIL step=offset-unaligned code=%d offset=0x%x",
                               GP107_ERR_OFFSET, offset);
    if (offset > GP107_MMIO_WINDOW - 4u)
        return gp107_set_error(err, errsz, "MMIO-FAIL step=offset-out-of-window code=%d offset=0x%x",
                               GP107_ERR_OFFSET, offset);
    if (inv.pci.bar0_size == 0 || (uint64_t)offset + 4u > (uint64_t)inv.pci.bar0_size)
        return gp107_set_error(err, errsz,
                               "MMIO-FAIL step=offset-out-of-resource code=%d offset=0x%x size=0x%x",
                               GP107_ERR_OFFSET, offset, inv.pci.bar0_size);

    /* No read-safe register has been proven. Return deferred before any BAR I/O. */
    return gp107_set_error(err, errsz,
                           "MMIO-FAIL step=read-safe-offset-unproven code=%d offset=0x%x",
                           GP107_ERR_READ_SAFE_OFFSET, offset);
}
