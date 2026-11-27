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

int gp107_mmio_read32(const char *sysfs_root,
                      const struct gp107_inventory *inv,
                      uint32_t offset, uint32_t *value,
                      char *err, size_t errsz)
{
    char path[512];
    int fd;
    void *map;
    volatile const unsigned char *p;
    uint32_t v;
    int n;

    if (sysfs_root == NULL || inv == NULL || value == NULL) {
        return gp107_set_error(err, errsz,
                               "MMIO-FAIL step=bad-argument code=%d",
                               GP107_ERR_USAGE);
    }
    if (inv->pci.bar0_size < GP107_MMIO_WINDOW) {
        return gp107_set_error(err, errsz,
                               "MMIO-FAIL step=bar0-size-too-small code=%d size=0x%x",
                               GP107_ERR_SIZE, inv->pci.bar0_size);
    }
    if (offset > GP107_MMIO_WINDOW - 4u) {
        return gp107_set_error(err, errsz,
                               "MMIO-FAIL step=offset-out-of-window code=%d offset=0x%x",
                               GP107_ERR_OFFSET, offset);
    }
    if ((uint64_t)offset + 4u > inv->pci.bar0_size) {
        return gp107_set_error(err, errsz,
                               "MMIO-FAIL step=offset-out-of-range code=%d offset=0x%x",
                               GP107_ERR_SIZE, offset);
    }
    n = snprintf(path, sizeof(path), "%s/bus/pci/devices/%s/resource0",
                 sysfs_root, inv->bdf);
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
