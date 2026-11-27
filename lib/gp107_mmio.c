#include "gp107_mmio.h"

#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
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

static int require_unbound_at(int dirfd, char *err, size_t errsz)
{
    char target[512];
    const char *base;
    ssize_t n;
    int saved;

    errno = 0;
    n = readlinkat(dirfd, "driver", target, sizeof(target) - 1);
    saved = errno;
    if (n < 0) {
        if (saved == ENOENT) {
            return GP107_OK;
        }
        return gp107_set_error(err, errsz,
                               "MMIO-FAIL step=driver-binding-read code=%d errno=%d",
                               GP107_ERR_DRIVER_BINDING, saved);
    }
    if (n == 0 || (size_t)n >= sizeof(target) - 1) {
        return gp107_set_error(err, errsz,
                               "MMIO-FAIL step=driver-binding-read code=%d",
                               GP107_ERR_DRIVER_BINDING);
    }

    target[n] = '\0';
    base = strrchr(target, '/');
    base = (base != NULL) ? base + 1 : target;
    if (*base == '\0') {
        return gp107_set_error(err, errsz,
                               "MMIO-FAIL step=driver-binding-read code=%d",
                               GP107_ERR_DRIVER_BINDING);
    }
    return gp107_set_error(err, errsz,
                           "MMIO-FAIL step=driver-bound code=%d driver=%s",
                           GP107_ERR_DRIVER_BOUND, base);
}

static int read_small_at(int dirfd, const char *name, char *buf, size_t cap)
{
    int fd;
    ssize_t n;
    int saved;

    if (buf == NULL || cap < 2) {
        errno = EINVAL;
        return -1;
    }
    fd = openat(dirfd, name,
                O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK);
    if (fd < 0) {
        return -1;
    }
    n = read(fd, buf, cap - 1);
    saved = errno;
    (void)close(fd);
    if (n < 0) {
        errno = saved;
        return -1;
    }
    if ((size_t)n >= cap - 1) {
        errno = EOVERFLOW;
        return -1;
    }
    buf[n] = '\0';
    return (int)n;
}

static int parse_hex16_text(const char *text, uint16_t *out)
{
    char *end = NULL;
    unsigned long value;

    if (text == NULL || out == NULL) {
        return -1;
    }
    errno = 0;
    value = strtoul(text, &end, 0);
    if (errno != 0 || end == text || value > 0xffffu) {
        return -1;
    }
    while (*end == '\n' || *end == '\r' || *end == ' ' || *end == '\t') {
        end++;
    }
    if (*end != '\0') {
        return -1;
    }
    *out = (uint16_t)value;
    return 0;
}

static int parse_hex_pair(const char *text, uint16_t *first, uint16_t *second)
{
    char left[8];
    const char *colon;
    char *end = NULL;
    unsigned long a;
    unsigned long b;
    size_t length;

    if (text == NULL || first == NULL || second == NULL) {
        return -1;
    }
    colon = strchr(text, ':');
    if (colon == NULL) {
        return -1;
    }
    length = (size_t)(colon - text);
    if (length == 0 || length >= sizeof(left) || colon[1] == '\0') {
        return -1;
    }
    memcpy(left, text, length);
    left[length] = '\0';
    errno = 0;
    a = strtoul(left, &end, 16);
    if (errno != 0 || end == left || *end != '\0' || a > 0xffffu) {
        return -1;
    }
    errno = 0;
    b = strtoul(colon + 1, &end, 16);
    if (errno != 0 || end == colon + 1 || b > 0xffffu) {
        return -1;
    }
    while (*end == '\n' || *end == '\r' || *end == ' ' || *end == '\t') {
        end++;
    }
    if (*end != '\0') {
        return -1;
    }
    *first = (uint16_t)a;
    *second = (uint16_t)b;
    return 0;
}

static int uevent_value(const char *uevent, const char *key,
                        char *value, size_t value_cap)
{
    size_t key_len;
    const char *line;

    if (uevent == NULL || key == NULL || value == NULL || value_cap == 0) {
        return -1;
    }
    key_len = strlen(key);
    line = uevent;
    while (*line != '\0') {
        const char *end = strchr(line, '\n');
        size_t line_len = end != NULL ? (size_t)(end - line) : strlen(line);
        if (line_len > key_len && memcmp(line, key, key_len) == 0 &&
            line[key_len] == '=') {
            size_t value_len = line_len - key_len - 1;
            if (value_len == 0 || value_len >= value_cap) {
                return -1;
            }
            memcpy(value, line + key_len + 1, value_len);
            value[value_len] = '\0';
            if (value_len > 0 && value[value_len - 1] == '\r') {
                value[value_len - 1] = '\0';
            }
            return 0;
        }
        if (end == NULL) {
            break;
        }
        line = end + 1;
    }
    return -1;
}

/* Validate the directory actually held by dirfd, not the BDF path that was
 * resolved earlier by gp107_inventory_scan(). A sysfs BDF entry is a symlink,
 * so the path can be retargeted between inventory and this open(). */
static int verify_pinned_identity(int dirfd, const char *expect_bdf,
                                  const struct gp107_inventory *expected,
                                  char *err, size_t errsz)
{
    char vendor_text[32];
    char device_text[32];
    char revision_text[32];
    char subsystem_vendor_text[32];
    char subsystem_device_text[32];
    char uevent[2048];
    char slot_name[64];
    char pci_id[64];
    char pci_subsystem_id[64];
    unsigned char config[GP107_CONFIG_BYTES];
    uint16_t vendor;
    uint16_t device;
    uint16_t revision;
    uint16_t subsystem_vendor;
    uint16_t subsystem_device;
    uint16_t event_vendor;
    uint16_t event_device;
    uint16_t event_subsystem_vendor;
    uint16_t event_subsystem_device;
    int fd;
    ssize_t n;
    int saved;

    if (expected == NULL || expect_bdf == NULL ||
        strcmp(expect_bdf, expected->bdf) != 0) {
        return gp107_set_error(err, errsz,
                               "MMIO-FAIL step=pinned-bdf-mismatch code=%d expected=%s inventory=%s",
                               GP107_ERR_BDF,
                               expect_bdf != NULL ? expect_bdf : "(null)",
                               expected != NULL ? expected->bdf : "(null)");
    }

    if (read_small_at(dirfd, "uevent", uevent, sizeof(uevent)) < 0 ||
        uevent_value(uevent, "PCI_SLOT_NAME", slot_name, sizeof(slot_name)) != 0) {
        return gp107_set_error(err, errsz,
                               "MMIO-FAIL step=pinned-uevent-read code=%d errno=%d",
                               GP107_ERR_CONFIG, errno);
    }
    if (strcmp(slot_name, expect_bdf) != 0) {
        return gp107_set_error(err, errsz,
                               "MMIO-FAIL step=pinned-bdf-mismatch code=%d expected=%s got=%s",
                               GP107_ERR_BDF, expect_bdf, slot_name);
    }

    if (read_small_at(dirfd, "vendor", vendor_text, sizeof(vendor_text)) < 0 ||
        read_small_at(dirfd, "device", device_text, sizeof(device_text)) < 0 ||
        read_small_at(dirfd, "revision", revision_text, sizeof(revision_text)) < 0 ||
        read_small_at(dirfd, "subsystem_vendor", subsystem_vendor_text,
                      sizeof(subsystem_vendor_text)) < 0 ||
        read_small_at(dirfd, "subsystem_device", subsystem_device_text,
                      sizeof(subsystem_device_text)) < 0 ||
        parse_hex16_text(vendor_text, &vendor) != 0 ||
        parse_hex16_text(device_text, &device) != 0 ||
        parse_hex16_text(revision_text, &revision) != 0 ||
        parse_hex16_text(subsystem_vendor_text, &subsystem_vendor) != 0 ||
        parse_hex16_text(subsystem_device_text, &subsystem_device) != 0) {
        return gp107_set_error(err, errsz,
                               "MMIO-FAIL step=pinned-pci-attributes code=%d errno=%d",
                               GP107_ERR_CONFIG, errno);
    }

    if (uevent_value(uevent, "PCI_ID", pci_id, sizeof(pci_id)) != 0 ||
        uevent_value(uevent, "PCI_SUBSYS_ID", pci_subsystem_id,
                     sizeof(pci_subsystem_id)) != 0 ||
        parse_hex_pair(pci_id, &event_vendor, &event_device) != 0 ||
        parse_hex_pair(pci_subsystem_id, &event_subsystem_vendor,
                       &event_subsystem_device) != 0) {
        return gp107_set_error(err, errsz,
                               "MMIO-FAIL step=pinned-pci-uevent code=%d",
                               GP107_ERR_CONFIG);
    }

    fd = openat(dirfd, "config",
                O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK);
    if (fd < 0) {
        return gp107_set_error(err, errsz,
                               "MMIO-FAIL step=pinned-config-open code=%d errno=%d",
                               GP107_ERR_CONFIG, errno);
    }
    memset(config, 0, sizeof(config));
    n = pread(fd, config, sizeof(config), 0);
    saved = errno;
    (void)close(fd);
    if (n < (ssize_t)sizeof(config)) {
        return gp107_set_error(err, errsz,
                               "MMIO-FAIL step=pinned-config-read code=%d errno=%d",
                               GP107_ERR_CONFIG, n < 0 ? saved : EIO);
    }

    if (vendor != GP107_PCI_VENDOR_NVIDIA ||
        device != GP107_PCI_DEVICE_GP107 ||
        vendor != expected->pci.vendor ||
        device != expected->pci.device ||
        event_vendor != vendor || event_device != device ||
        event_subsystem_vendor != subsystem_vendor ||
        event_subsystem_device != subsystem_device ||
        revision != expected->pci.revision ||
        config[0] != (unsigned char)(vendor & 0xffu) ||
        config[1] != (unsigned char)(vendor >> 8) ||
        config[2] != (unsigned char)(device & 0xffu) ||
        config[3] != (unsigned char)(device >> 8) ||
        config[0x08] != (unsigned char)revision) {
        return gp107_set_error(err, errsz,
                               "MMIO-FAIL step=pinned-pci-identity code=%d bdf=%s vendor=0x%04x device=0x%04x revision=0x%02x",
                               GP107_ERR_CONFIG, expect_bdf,
                               vendor, device, revision);
    }
    return GP107_OK;
}

static int map_read32(const char *sysfs_root, const char *bdf,
                      const struct gp107_inventory *expected_identity,
                      uint32_t expected_size, uint32_t offset, uint32_t *value,
                      char *err, size_t errsz)
{
    char devdir[512];
    int dirfd = -1;
    int fd = -1;
    void *map;
    volatile const unsigned char *p;
    uint32_t v;
    int n;
    int rc;
    struct stat dir_st;
    struct stat resource_st;

    n = snprintf(devdir, sizeof(devdir), "%s/bus/pci/devices/%s",
                 sysfs_root, bdf);
    if (n < 0 || (size_t)n >= sizeof(devdir)) {
        return gp107_set_error(err, errsz,
                               "MMIO-FAIL step=path-too-long code=%d",
                               GP107_ERR_PARSE);
    }

    /* Pin one PCI device directory. Binding checks and resource0 opening then
     * use that same directory descriptor rather than resolving fresh paths. */
    dirfd = open(devdir, O_RDONLY | O_CLOEXEC);
    if (dirfd < 0) {
        return gp107_set_error(err, errsz,
                               "MMIO-FAIL step=device-directory-open code=%d errno=%d",
                               GP107_ERR_OPEN, errno);
    }
    errno = 0;
    if (fstat(dirfd, &dir_st) != 0) {
        int saved = errno;
        (void)close(dirfd);
        return gp107_set_error(err, errsz,
                               "MMIO-FAIL step=device-directory-stat code=%d errno=%d",
                               GP107_ERR_OPEN, saved);
    }
    if (!S_ISDIR(dir_st.st_mode)) {
        (void)close(dirfd);
        return gp107_set_error(err, errsz,
                               "MMIO-FAIL step=device-directory-stat code=%d errno=%d",
                               GP107_ERR_OPEN, ENOTDIR);
    }

    rc = verify_pinned_identity(dirfd, bdf, expected_identity, err, errsz);
    if (rc != GP107_OK) {
        (void)close(dirfd);
        return rc;
    }

    rc = require_unbound_at(dirfd, err, errsz);
    if (rc != GP107_OK) {
        (void)close(dirfd);
        return rc;
    }

    /* O_NOFOLLOW rejects a substituted resource0 symlink. O_NONBLOCK also
     * prevents hanging if that path is replaced by a FIFO. */
    fd = openat(dirfd, "resource0",
                O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK);
    if (fd < 0) {
        int saved = errno;
        (void)close(dirfd);
        return gp107_set_error(err, errsz,
                               "MMIO-FAIL step=resource0-open code=%d errno=%d",
                               GP107_ERR_OPEN, saved);
    }
    if (fstat(fd, &resource_st) != 0) {
        int saved = errno;
        (void)close(fd);
        (void)close(dirfd);
        return gp107_set_error(err, errsz,
                               "MMIO-FAIL step=bar0-stat code=%d errno=%d",
                               GP107_ERR_SIZE, saved);
    }
    if (!S_ISREG(resource_st.st_mode) ||
        resource_st.st_size < (off_t)GP107_MMIO_WINDOW ||
        resource_st.st_size != (off_t)expected_size) {
        off_t size = resource_st.st_size;
        int regular = S_ISREG(resource_st.st_mode);
        (void)close(fd);
        (void)close(dirfd);
        return gp107_set_error(err, errsz,
                               "MMIO-FAIL step=bar0-size-too-small code=%d size=0x%llx regular=%d",
                               GP107_ERR_SIZE, (unsigned long long)size, regular);
    }

    /* Recheck immediately before mmap. This narrows the window but is not an
     * atomic lock against a later kernel driver bind. */
    rc = require_unbound_at(dirfd, err, errsz);
    if (rc != GP107_OK) {
        (void)close(fd);
        (void)close(dirfd);
        return rc;
    }

    map = mmap(NULL, GP107_MMIO_WINDOW, PROT_READ, MAP_SHARED, fd, 0);
    if (map == MAP_FAILED) {
        int saved = errno;
        (void)close(fd);
        (void)close(dirfd);
        return gp107_set_error(err, errsz,
                               "MMIO-FAIL step=read-only-map code=%d errno=%d",
                               GP107_ERR_MAP, saved);
    }
    (void)close(fd);
    (void)close(dirfd);

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
    return map_read32(sysfs_root, inv.bdf, &inv, inv.pci.bar0_size,
                       offset, value, err, errsz);
}
