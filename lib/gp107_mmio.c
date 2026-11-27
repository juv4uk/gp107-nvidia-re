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

static int inventory_same_target(const struct gp107_inventory *before,
                                 const struct gp107_inventory *after,
                                 char *err, size_t errsz)
{
    if (before == NULL || after == NULL ||
        strcmp(before->bdf, after->bdf) != 0 ||
        before->pci.vendor != after->pci.vendor ||
        before->pci.device != after->pci.device ||
        before->pci.domain != after->pci.domain ||
        before->pci.bus != after->pci.bus ||
        before->pci.slot != after->pci.slot ||
        before->pci.function != after->pci.function ||
        before->pci.bar0_raw != after->pci.bar0_raw ||
        before->pci.bar0_base != after->pci.bar0_base ||
        before->pci.bar0_size != after->pci.bar0_size ||
        before->pci.bar0_space != after->pci.bar0_space ||
        before->pci.bar0_width != after->pci.bar0_width ||
        before->pci.bar0_prefetch != after->pci.bar0_prefetch ||
        before->pci.cfg_bytes != after->pci.cfg_bytes ||
        before->pci.command != after->pci.command) {
        return gp107_set_error(err, errsz,
                               "MMIO-FAIL step=inventory-changed code=%d",
                               GP107_ERR_CONFIG);
    }
    return GP107_OK;
}

int gp107_mmio_read32(const char *sysfs_root,
                      const struct gp107_inventory *provided, int allow_mmio,
                      uint32_t offset, uint32_t *value,
                      char *err, size_t errsz)
{
    char path[512];
    struct gp107_inventory inv;
    struct gp107_inventory current;
    struct stat st;
    int fd;
    void *map;
    volatile const unsigned char *p;
    uint32_t v;
    int n;
    int rc;
    int saved;

    if (sysfs_root == NULL || provided == NULL || value == NULL ||
        err == NULL || errsz == 0 ||
        strnlen(provided->bdf, sizeof(provided->bdf)) == sizeof(provided->bdf) ||
        provided->bdf[0] == '\\0') {
        return gp107_set_error(err, errsz,
                               "MMIO-FAIL step=bad-argument code=%d",
                               GP107_ERR_USAGE);
    }

    /* The API must not trust a caller-supplied, possibly stale inventory. */
    rc = gp107_mmio_require_optin(allow_mmio, err, errsz);
    if (rc != GP107_OK) {
        return rc;
    }
    rc = gp107_inventory_scan(sysfs_root, provided->bdf, &inv, err, errsz);
    if (rc != GP107_OK) {
        return rc;
    }
    rc = gp107_mmio_check_driver(&inv, err, errsz);
    if (rc != GP107_OK) {
        return rc;
    }
    if (inv.pci.bar0_space != 0) {
        return gp107_set_error(err, errsz,
                               "MMIO-FAIL step=bar0-not-memory code=%d",
                               GP107_ERR_CONFIG);
    }
    if (inv.pci.bar0_size < GP107_MMIO_WINDOW) {
        return gp107_set_error(err, errsz,
                               "MMIO-FAIL step=bar0-size-too-small code=%d size=0x%x",
                               GP107_ERR_SIZE, inv.pci.bar0_size);
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
    if ((uint64_t)offset + 4u > inv.pci.bar0_size) {
        return gp107_set_error(err, errsz,
                               "MMIO-FAIL step=offset-out-of-resource code=%d offset=0x%x size=0x%x",
                               GP107_ERR_SIZE, offset, inv.pci.bar0_size);
    }

    n = snprintf(path, sizeof(path), "%s/bus/pci/devices/%s/resource0",
                 sysfs_root, inv.bdf);
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
    if (st.st_size < (off_t)GP107_MMIO_WINDOW ||
        st.st_size != (off_t)inv.pci.bar0_size ||
        (uint64_t)offset + 4u > (uint64_t)st.st_size) {
        (void)close(fd);
        return gp107_set_error(err, errsz,
                               "MMIO-FAIL step=resource0-size-too-small code=%d size=%lld offset=0x%x",
                               GP107_ERR_SIZE, (long long)st.st_size, offset);
    }

    /* sysfs has no exclusive bind lock; recheck immediately before mapping. */
    rc = gp107_inventory_scan(sysfs_root, inv.bdf, &current, err, errsz);
    if (rc == GP107_OK) {
        rc = inventory_same_target(&inv, &current, err, errsz);
    }
    if (rc == GP107_OK) {
        rc = gp107_mmio_check_driver(&current, err, errsz);
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
    rc = gp107_inventory_scan(sysfs_root, inv.bdf, &current, err, errsz);
    if (rc == GP107_OK) {
        rc = inventory_same_target(&inv, &current, err, errsz);
    }
    if (rc == GP107_OK) {
        rc = gp107_mmio_check_driver(&current, err, errsz);
    }
    if (rc != GP107_OK) {
        (void)munmap(map, GP107_MMIO_WINDOW);
        return rc;
    }

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
