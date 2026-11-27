#include "gp107_mmio.h"

#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>

int gp107_mmio_require_optin(int allow, char *err, size_t errsz)
{
    if (!allow) {
        return gp107_set_error(err, errsz,
                               "MMIO-FAIL step=opt-in-required code=%d",
                               GP107_ERR_OPTIN);
    }
    return GP107_OK;
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

int gp107_mmio_read32(const char *sysfs_root, const char *bdf, int allow_mmio,
                      uint32_t offset, uint32_t *value,
                      char *err, size_t errsz)
{
    char path[512];
    struct gp107_inventory inv;
    struct stat st;
    int fd;
    void *map;
    volatile const unsigned char *p;
    uint32_t v;
    int n;
    int rc;
    int saved;

    if (sysfs_root == NULL || bdf == NULL || value == NULL ||
        err == NULL || errsz == 0) {
        return GP107_ERR_USAGE;
    }

    /* Keep policy at the API boundary, not only in the CLI caller. */
    rc = gp107_mmio_require_optin(allow_mmio, err, errsz);
    if (rc != GP107_OK) {
        return rc;
    }
    rc = gp107_inventory_scan(sysfs_root, bdf, &inv, err, errsz);
    if (rc != GP107_OK) {
        return rc;
    }
    rc = gp107_mmio_check_driver(&inv, err, errsz);
    if (rc != GP107_OK) {
        return rc;
    }

    if (offset > GP107_MMIO_WINDOW - 4u) {
        return gp107_set_error(err, errsz,
                               "MMIO-FAIL step=offset-out-of-window code=%d offset=0x%x",
                               GP107_ERR_OFFSET, offset);
    }
    if ((offset & 3u) != 0) {
        return gp107_set_error(err, errsz,
                               "MMIO-FAIL step=offset-unaligned code=%d offset=0x%x",
                               GP107_ERR_OFFSET, offset);
    }

    n = snprintf(path, sizeof(path), "%s/bus/pci/devices/%s/resource0",
                 sysfs_root, bdf);
    if (n < 0 || (size_t)n >= sizeof(path)) {
        return gp107_set_error(err, errsz,
                               "MMIO-FAIL step=path-too-long code=%d",
                               GP107_ERR_PARSE);
    }
    fd = open(path, O_RDONLY | O_CLOEXEC);
    if (fd < 0) {
        saved = errno;
        return gp107_set_error(err, errsz,
                               "MMIO-FAIL step=resource0-open code=%d errno=%d",
                               GP107_ERR_OPEN, saved);
    }
    if (fstat(fd, &st) != 0) {
        saved = errno;
        (void)close(fd);
        return gp107_set_error(err, errsz,
                               "MMIO-FAIL step=resource0-stat code=%d errno=%d",
                               GP107_ERR_READ, saved);
    }
    if (st.st_size < 0 || (uint64_t)st.st_size < (uint64_t)offset + 4u) {
        (void)close(fd);
        return gp107_set_error(err, errsz,
                               "MMIO-FAIL step=offset-out-of-resource code=%d offset=0x%x size=%lld",
                               GP107_ERR_OFFSET, offset, (long long)st.st_size);
    }

    /* Re-check the binding after opening the resource and immediately before
     * mapping; the earlier inventory alone is not a stable driver lock. */
    rc = gp107_inventory_scan(sysfs_root, bdf, &inv, err, errsz);
    if (rc == GP107_OK) {
        rc = gp107_mmio_check_driver(&inv, err, errsz);
    }
    if (rc != GP107_OK) {
        (void)close(fd);
        return rc;
    }

    map = mmap(NULL, GP107_MMIO_WINDOW, PROT_READ, MAP_SHARED, fd, 0);
    if (map == MAP_FAILED) {
        saved = errno;
        (void)close(fd);
        return gp107_set_error(err, errsz,
                               "MMIO-FAIL step=read-only-map code=%d errno=%d",
                               GP107_ERR_MAP, saved);
    }
    (void)close(fd);

    /* Last best-effort binding check before the actual read. */
    rc = gp107_inventory_scan(sysfs_root, bdf, &inv, err, errsz);
    if (rc == GP107_OK) {
        rc = gp107_mmio_check_driver(&inv, err, errsz);
    }
    if (rc != GP107_OK) {
        (void)munmap(map, GP107_MMIO_WINDOW);
        return rc;
    }

    p = (const volatile unsigned char *)map + offset;
    v = (uint32_t)p[0] | ((uint32_t)p[1] << 8) |
        ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
    (void)munmap(map, GP107_MMIO_WINDOW);
    *value = v;
    return GP107_OK;
}
