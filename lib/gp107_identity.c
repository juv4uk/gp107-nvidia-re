#include "gp107_identity.h"

#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#define GP107_PATH_CAP 512
#define GP107_CFG_BYTES ((size_t)GP107_CONFIG_BYTES)

int gp107_set_error(char *err, size_t errsz, const char *fmt, ...)
{
    va_list ap;
    int code = 0;

    if (err != NULL && errsz > 0) {
        va_start(ap, fmt);
        (void)vsnprintf(err, errsz, fmt, ap);
        va_end(ap);
        err[errsz - 1] = '\0';
    }
    /* Return the semantic code carried by the named step marker. */
    if (err != NULL &&
        (sscanf(err, "IDENTITY-FAIL step=%*[^ ] code=%d", &code) == 1 ||
         sscanf(err, "MMIO-FAIL step=%*[^ ] code=%d", &code) == 1) &&
        code > 0) {
        return code;
    }
    return GP107_ERR_PARSE;
}

static int join_path(char *dst, size_t cap, const char *a, const char *b)
{
    int n = snprintf(dst, cap, "%s/%s", a, b);
    if (n < 0 || (size_t)n >= cap) {
        return -1;
    }
    return 0;
}

static int read_small_file(const char *path, char *buf, size_t cap)
{
    int fd = open(path, O_RDONLY | O_CLOEXEC);
    ssize_t n;
    int saved;

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
    buf[n] = '\0';
    return (int)n;
}

static int parse_hex16(const char *s, uint16_t *out)
{
    const char *p = s;
    char *end = NULL;
    unsigned long v;

    if (p[0] == '0' && (p[1] == 'x' || p[1] == 'X')) {
        p += 2;
    }
    errno = 0;
    v = strtoul(p, &end, 16);
    if (errno != 0 || end == p || v > 0xffffu) {
        return -1;
    }
    while (*end == '\n' || *end == '\r' || *end == ' ' || *end == '\t') {
        end++;
    }
    if (*end != '\0') {
        return -1;
    }
    *out = (uint16_t)v;
    return 0;
}

static int read_config(const char *path, unsigned char bytes[GP107_CFG_BYTES])
{
    int fd = open(path, O_RDONLY | O_CLOEXEC);
    ssize_t n;
    int saved;

    if (fd < 0) {
        return -1;
    }
    memset(bytes, 0, GP107_CFG_BYTES);
    n = pread(fd, bytes, GP107_CFG_BYTES, 0);
    saved = errno;
    (void)close(fd);
    if (n < 0) {
        errno = saved;
        return -1;
    }
    if (n < (ssize_t)GP107_CFG_BYTES) {
        return -1;
    }
    return 0;
}

static int parse_bdf(const char *name, struct gp107_pci_identity *id,
                     char *bdf, size_t bdfsz)
{
    unsigned int domain = 0;
    unsigned int bus = 0;
    unsigned int slot = 0;
    unsigned int func = 0;

    if (sscanf(name, "%4x:%2x:%2x.%u", &domain, &bus, &slot, &func) != 4) {
        return -1;
    }
    if (domain > 0xffffu || bus > 0xffu || slot > 0x1fu || func > 7u) {
        return -1;
    }
    id->domain = (uint16_t)domain;
    id->bus = (uint8_t)bus;
    id->slot = (uint8_t)slot;
    id->function = (uint8_t)func;
    if (snprintf(bdf, bdfsz, "%04x:%02x:%02x.%u",
                 domain, bus, slot, func) >= (int)bdfsz) {
        return -1;
    }
    return 0;
}

static int read_driver_link(const char *devdir,
                             struct gp107_driver_binding *out,
                             char *err, size_t errsz)
{
    char path[GP107_PATH_CAP];
    char target[GP107_PATH_CAP];
    ssize_t n;
    const char *base;
    size_t len;

    memset(out, 0, sizeof(*out));
    if (join_path(path, sizeof(path), devdir, "driver") != 0) {
        return gp107_set_error(err, errsz,
                               "IDENTITY-FAIL step=driver-binding-path code=%d",
                               GP107_ERR_DRIVER_BINDING);
    }

    errno = 0;
    n = readlink(path, target, sizeof(target) - 1);
    if (n < 0) {
        int saved = errno;
        /* A missing sysfs driver link is the one and only unbound witness. */
        if (saved == ENOENT) {
            return GP107_OK;
        }
        return gp107_set_error(err, errsz,
                               "IDENTITY-FAIL step=driver-binding-read code=%d errno=%d",
                               GP107_ERR_DRIVER_BINDING, saved);
    }
    if (n == 0 || (size_t)n >= sizeof(target) - 1) {
        return gp107_set_error(err, errsz,
                               "IDENTITY-FAIL step=driver-binding-read code=%d",
                               GP107_ERR_DRIVER_BINDING);
    }

    target[n] = '\0';
    base = strrchr(target, '/');
    base = (base != NULL) ? base + 1 : target;
    len = strlen(base);
    if (len == 0 || len >= sizeof(out->name)) {
        return gp107_set_error(err, errsz,
                               "IDENTITY-FAIL step=driver-binding-read code=%d",
                               GP107_ERR_DRIVER_BINDING);
    }
    memcpy(out->name, base, len);
    out->name[len] = '\0';
    out->bound = 1;
    return GP107_OK;
}

static void read_bar0_size(const char *devdir, struct gp107_pci_identity *id)
{
    char path[GP107_PATH_CAP];
    struct stat st;

    id->bar0_size = 0;
    if (join_path(path, sizeof(path), devdir, "resource0") != 0) {
        return;
    }
    if (stat(path, &st) == 0 && st.st_size > 0) {
        id->bar0_size = (uint32_t)(((uint64_t)st.st_size) & 0xffffffffu);
    }
}

int gp107_inventory_scan(const char *sysfs_root, const char *expect_bdf,
                         struct gp107_inventory *out, char *err, size_t errsz)
{
    char devdir[GP107_PATH_CAP];
    char path[GP107_PATH_CAP];
    char text[64];
    char found_bdf[32];
    unsigned char cfg[GP107_CFG_BYTES];
    struct gp107_pci_identity candidate;
    DIR *dir = NULL;
    struct dirent *de;
    uint16_t sv = 0;
    uint16_t sd = 0;
    uint16_t cv = 0;
    uint16_t cd = 0;
    int rc = GP107_OK;

    if (err != NULL && errsz > 0) {
        err[0] = '\0';
    }
    if (sysfs_root == NULL || expect_bdf == NULL || out == NULL || err == NULL || errsz == 0) {
        return gp107_set_error(err, errsz, "IDENTITY-FAIL step=bad-argument code=%d",
                               GP107_ERR_USAGE);
    }
    memset(out, 0, sizeof(*out));
    found_bdf[0] = '\0';

    if (snprintf(devdir, sizeof(devdir), "%s/bus/pci/devices", sysfs_root) >=
        (int)sizeof(devdir)) {
        return gp107_set_error(err, errsz, "IDENTITY-FAIL step=path-too-long code=%d",
                               GP107_ERR_PARSE);
    }
    dir = opendir(devdir);
    if (dir == NULL) {
        return gp107_set_error(err, errsz,
                               "IDENTITY-FAIL step=pci-devices-open code=%d",
                               GP107_ERR_OPEN);
    }

    while ((de = readdir(dir)) != NULL) {
        if (strcmp(de->d_name, ".") == 0 || strcmp(de->d_name, "..") == 0) {
            continue;
        }
        if (join_path(path, sizeof(path), devdir, de->d_name) != 0) {
            rc = gp107_set_error(err, errsz,
                                 "IDENTITY-FAIL step=device-path code=%d",
                                 GP107_ERR_PARSE);
            goto done;
        }

        char vpath[GP107_PATH_CAP];
        char dpath[GP107_PATH_CAP];
        char cpath[GP107_PATH_CAP];
        if (join_path(vpath, sizeof(vpath), path, "vendor") != 0 ||
            join_path(dpath, sizeof(dpath), path, "device") != 0 ||
            join_path(cpath, sizeof(cpath), path, "config") != 0) {
            rc = gp107_set_error(err, errsz,
                                 "IDENTITY-FAIL step=device-path code=%d",
                                 GP107_ERR_PARSE);
            goto done;
        }
        if (read_small_file(vpath, text, sizeof(text)) < 0 ||
            parse_hex16(text, &sv) != 0) {
            /* Not a PCI device directory in this fixture/host view. */
            continue;
        }
        if (read_small_file(dpath, text, sizeof(text)) < 0 ||
            parse_hex16(text, &sd) != 0) {
            continue;
        }
        if (sv != GP107_PCI_VENDOR_NVIDIA || sd != GP107_PCI_DEVICE_GP107) {
            continue;
        }
        out->candidate_count++;

        if (read_config(cpath, cfg) != 0) {
            rc = gp107_set_error(err, errsz,
                                 "IDENTITY-FAIL step=pci-config-read code=%d bdf=%s",
                                 GP107_ERR_CONFIG, de->d_name);
            goto done;
        }
        cv = (uint16_t)((uint16_t)cfg[0] | ((uint16_t)cfg[1] << 8));
        cd = (uint16_t)((uint16_t)cfg[2] | ((uint16_t)cfg[3] << 8));
        if (cv != sv || cd != sd) {
            rc = gp107_set_error(err, errsz,
                                 "IDENTITY-FAIL step=pci-config-mismatch code=%d bdf=%s",
                                 GP107_ERR_CONFIG, de->d_name);
            goto done;
        }
        memset(&candidate, 0, sizeof(candidate));
        candidate.vendor = cv;
        candidate.device = cd;
        candidate.command = (uint16_t)((uint16_t)cfg[0x04] | ((uint16_t)cfg[0x05] << 8));
        candidate.revision = cfg[0x08];
        candidate.class_code[0] = cfg[0x09];
        candidate.class_code[1] = cfg[0x0a];
        candidate.class_code[2] = cfg[0x0b];
        candidate.header_type = cfg[0x0e];
        candidate.bar0_raw = (uint32_t)cfg[0x10] |
                             ((uint32_t)cfg[0x11] << 8) |
                             ((uint32_t)cfg[0x12] << 16) |
                             ((uint32_t)cfg[0x13] << 24);
        {
            unsigned int flags = candidate.bar0_raw & 0x0fu;
            candidate.bar0_space = (flags & 1u) ? 1u : 0u;
            candidate.bar0_width = (((flags >> 1) & 3u) == 2u) ? 1u : 0u;
            candidate.bar0_prefetch = (flags & 8u) ? 1u : 0u;
            candidate.bar0_base = candidate.bar0_raw &
                                  (candidate.bar0_space ? 0xfffffffcu : 0xfffffff0u);
        }
        candidate.cfg_bytes = GP107_CONFIG_BYTES;
        if (parse_bdf(de->d_name, &candidate, found_bdf, sizeof(found_bdf)) != 0) {
            rc = gp107_set_error(err, errsz,
                                 "IDENTITY-FAIL step=bdf-parse code=%d name=%s",
                                 GP107_ERR_PARSE, de->d_name);
            goto done;
        }
        rc = read_driver_link(path, &out->driver, err, errsz);
        if (rc != GP107_OK) {
            goto done;
        }
        read_bar0_size(path, &candidate);
        out->pci = candidate;
        out->valid_count++;
    }

    if (out->candidate_count == 0) {
        rc = gp107_set_error(err, errsz,
                             "IDENTITY-FAIL step=pci-no-match code=%d",
                             GP107_ERR_NO_MATCH);
        goto done;
    }
    if (out->valid_count != 1) {
        rc = gp107_set_error(err, errsz,
                             "IDENTITY-FAIL step=card-count code=%d count=%d",
                             GP107_ERR_CARD_COUNT, out->valid_count);
        goto done;
    }
    if (strcmp(found_bdf, expect_bdf) != 0) {
        rc = gp107_set_error(err, errsz,
                             "IDENTITY-FAIL step=bdf-mismatch code=%d expected=%s got=%s",
                             GP107_ERR_BDF, expect_bdf, found_bdf);
        goto done;
    }
    (void)snprintf(out->bdf, sizeof(out->bdf), "%s", found_bdf);

done:
    if (dir != NULL) {
        (void)closedir(dir);
    }
    return rc;
}
