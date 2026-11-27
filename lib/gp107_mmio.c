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
    /* Only bound=0 from a successful inventory means confirmed-unbound. */
    if (inv->driver.bound != 0) {
        return gp107_set_error(err, errsz,
                               "MMIO-FAIL step=driver-not-confirmed-unbound code=%d driver=%s",
                               GP107_ERR_DRIVER_BOUND,
                               inv->driver.name[0] ? inv->driver.name : "unknown");
    }
    return GP107_OK;
}

int gp107_mmio_read32(const char *sysfs_root, const char *expect_bdf,
                      int allow, uint32_t offset, uint32_t *value,
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

    if (err != NULL && errsz > 0) {
        err[0] = '\0';
    }
    if (value != NULL) {
        *value = 0;
    }
    if (sysfs_root == NULL || expect_bdf == NULL || value == NULL ||
        err == NULL || errsz == 0) {
        return gp107_set_error(err, errsz,
                               "MMIO-FAIL step=bad-argument code=%d",
                               GP107_ERR_USAGE);
    }

    /* These gates live in the public API, not just in gp107ctl. */
    rc = gp107_mmio_require_optin(allow, err, errsz);
    if (rc != GP107_OK) {
        return rc;
    }
    rc = gp107_inventory_scan(sysfs_root, expect_bdf, &inv, err, errsz);
    if (rc != GP107_OK) {
        return rc;
    }
    rc = gp107_mmio_check_driver(&inv, err, errsz);
    if (rc != GP107_OK) {
        return rc;
    }

    if ((offset & 3u) != 0u) {
        return gp107_set_error(err, errsz,
                               "MMIO-FAIL step=unaligned-offset code=%d offset=0x%x",
                               GP107_ERR_ALIGNMENT, offset);
    }
    if (offset > GP107_MMIO_WINDOW - 4u) {
        return gp107_set_error(err, errsz,
                               "MMIO-FAIL step=offset-out-of-window code=%d offset=0x%x",
                               GP107_ERR_OFFSET, offset);
    }

    /* Use the canonical BDF emitted by the successful inventory scan. */
    n = snprintf(path, sizeof(path), "%s/bus/pci/devices/%s/resource0",
                 sysfs_root, inv.bdf);
    if (n < 0 || (size_t)n >= sizeof(path)) {
        return gp107_set_error(err, errsz,
                               "MMIO-FAIL step=path-too-long code=%d",
                               GP107_ERR_PARSE);
    }
    fd = open(path, O_RDONLY | O_CLOEXEC);
    if (fd < 0) {
        return gp107_set_error(err, errsz,
                               "MMIO-FAIL step=resource0-open code=%d errno=%d",
                               GP107_ERR_OPEN, errno);
    }
    if (fstat(fd, &st) != 0) {
        int saved = errno;
        (void)close(fd);
        return gp107_set_error(err, errsz,
                               "MMIO-FAIL step=resource0-stat code=%d errno=%d",
                               GP107_ERR_READ, saved);
    }
    if (st.st_size < (off_t)GP107_MMIO_WINDOW) {
        off_t size = st.st_size;
        (void)close(fd);
        return gp107_set_error(err, errsz,
                               "MMIO-FAIL step=resource0-too-small code=%d size=%lld required=%u",
                               GP107_ERR_RESOURCE_SIZE, (long long)size,
                               GP107_MMIO_WINDOW);
    }

    map = mmap(NULL, GP107_MMIO_WINDOW, PROT_READ, MAP_SHARED, fd, 0);
    if (map == MAP_FAILED) {
        int saved = errno;
        (void)close(fd);
        return gp107_set_error(err, errsz,
                               "MMIO-FAIL step=read-only-map code=%d errno=%d",
                               GP107_ERR_MAP, saved);
    }
    (void)close(fd);

    p = (const volatile unsigned char *)map + offset;
#ifdef GP107_USE_ASM
    v = gp107_mmio_load32_asm((const volatile void *)p);
#else
    v = (uint32_t)p[0] | ((uint32_t)p[1] << 8) |
        ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
#endif
    (void)munmap(map, GP107_MMIO_WINDOW);
    *value = v;
    return GP107_OK;
}
