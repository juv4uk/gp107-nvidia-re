#include "gp107_mmio.h"

#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>

#ifdef GP107_USE_ASM
/* Private implementation detail; not part of the public MMIO API. */
extern uint32_t gp107_mmio_load32_asm(const volatile void *addr);
#endif

static int require_optin(int allow, char *err, size_t errsz)
{
    if (!allow) {
        return gp107_set_error(err, errsz,
                               "MMIO-FAIL step=opt-in-required code=%d",
                               GP107_ERR_OPTIN);
    }
    return GP107_OK;
}

static int require_unbound(const struct gp107_inventory *inv,
                           char *err, size_t errsz)
{
    if (inv->driver.bound) {
        return gp107_set_error(err, errsz,
                               "MMIO-FAIL step=driver-bound code=%d driver=%s",
                               GP107_ERR_DRIVER_BOUND, inv->driver.name);
    }
    return GP107_OK;
}

static int map_read32_fd(int fd, uint32_t expected_size,
                         uint32_t offset, uint32_t *value,
                         char *err, size_t errsz)
{
    struct stat st;
    void *map;
    volatile const unsigned char *p;
    uint32_t v;

    if (fstat(fd, &st) != 0) {
        int saved = errno;
        (void)close(fd);
        return gp107_set_error(err, errsz,
                               "MMIO-FAIL step=bar0-stat code=%d errno=%d",
                               GP107_ERR_SIZE, saved);
    }
    if (st.st_size < (off_t)GP107_MMIO_WINDOW ||
        st.st_size != (off_t)expected_size) {
        off_t size = st.st_size;
        (void)close(fd);
        return gp107_set_error(err, errsz,
                               "MMIO-FAIL step=bar0-size-too-small code=%d size=0x%llx",
                               GP107_ERR_SIZE, (unsigned long long)size);
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

int gp107_mmio_read32(const char *sysfs_root, const char *expect_bdf,
                      int allow, uint32_t offset, uint32_t *value,
                      char *err, size_t errsz)
{
    struct gp107_inventory inv;
    struct stat devst;
    char devpath[512];
    char driver_target[GP107_PATH_CAP];
    ssize_t link_len;
    int dirfd = -1;
    int fd = -1;
    int n;
    int rc;

    if (err == NULL || errsz == 0) {
        return GP107_ERR_USAGE;
    }
    err[0] = '\0';
    if (sysfs_root == NULL || expect_bdf == NULL || value == NULL) {
        return gp107_set_error(err, errsz,
                               "MMIO-FAIL step=bad-argument code=%d",
                               GP107_ERR_USAGE);
    }

    rc = require_optin(allow, err, errsz);
    if (rc != GP107_OK) {
        return rc;
    }
    rc = gp107_inventory_scan(sysfs_root, expect_bdf, &inv, err, errsz);
    if (rc != GP107_OK) {
        return rc;
    }
    rc = require_unbound(&inv, err, errsz);
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
                               "MMIO-FAIL step=bar0-size-too-small code=%d size=0x%x required=%u",
                               GP107_ERR_SIZE, inv.pci.bar0_size,
                               GP107_MMIO_WINDOW);
    }
    if ((offset & 3u) != 0) {
        return gp107_set_error(err, errsz,
                               "MMIO-FAIL step=offset-unaligned code=%d offset=0x%x",
                               GP107_ERR_OFFSET, offset);
    }
    if (offset > GP107_MMIO_WINDOW - 4u ||
        (uint64_t)offset + 4u > inv.pci.bar0_size) {
        return gp107_set_error(err, errsz,
                               "MMIO-FAIL step=offset-out-of-window code=%d offset=0x%x size=0x%x",
                               GP107_ERR_OFFSET, offset, inv.pci.bar0_size);
    }

    n = snprintf(devpath, sizeof(devpath), "%s/bus/pci/devices/%s",
                 sysfs_root, inv.bdf);
    if (n < 0 || (size_t)n >= sizeof(devpath)) {
        return gp107_set_error(err, errsz,
                               "MMIO-FAIL step=device-path-too-long code=%d",
                               GP107_ERR_PARSE);
    }

    /* Pin the resolved PCI device directory, re-check binding, and open
     * resource0 relative to that same directory fd. This narrows the TOCTOU
     * window; it is not an atomic lock against a later kernel driver bind. */
    dirfd = open(devpath, O_RDONLY | O_CLOEXEC);
    if (dirfd < 0) {
        return gp107_set_error(err, errsz,
                               "MMIO-FAIL step=device-dir-open code=%d errno=%d",
                               GP107_ERR_DRIVER_BINDING, errno);
    }
    if (fstat(dirfd, &devst) != 0) {
        int saved = errno;
        (void)close(dirfd);
        return gp107_set_error(err, errsz,
                               "MMIO-FAIL step=device-dir-stat code=%d errno=%d",
                               GP107_ERR_DRIVER_BINDING, saved);
    }
    if (!S_ISDIR(devst.st_mode)) {
        (void)close(dirfd);
        return gp107_set_error(err, errsz,
                               "MMIO-FAIL step=device-dir-invalid code=%d",
                               GP107_ERR_DRIVER_BINDING);
    }

    errno = 0;
    link_len = readlinkat(dirfd, "driver", driver_target,
                          sizeof(driver_target));
    if (link_len >= 0) {
        (void)close(dirfd);
        return gp107_set_error(err, errsz,
                               "MMIO-FAIL step=driver-bound code=%d",
                               GP107_ERR_DRIVER_BOUND);
    }
    if (errno != ENOENT) {
        int saved = errno;
        (void)close(dirfd);
        return gp107_set_error(err, errsz,
                               "MMIO-FAIL step=driver-binding-recheck code=%d errno=%d",
                               GP107_ERR_DRIVER_BINDING, saved);
    }

    fd = openat(dirfd, "resource0", O_RDONLY | O_CLOEXEC | O_NOFOLLOW);
    if (fd < 0) {
        int saved = errno;
        (void)close(dirfd);
        return gp107_set_error(err, errsz,
                               "MMIO-FAIL step=resource0-open code=%d errno=%d",
                               GP107_ERR_OPEN, saved);
    }
    (void)close(dirfd);

    return map_read32_fd(fd, inv.pci.bar0_size, offset, value, err, errsz);
}
