#define _POSIX_C_SOURCE 200809L

#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "gp107_identity.h"
#include "gp107_mmio.h"

static int usage(void)
{
    fprintf(stderr,
            "USAGE gp107ctl inventory [--sysfs-root=PATH] [--expect-bdf=BDF]\n"
            "      gp107ctl mmio-read --offset=0xNN [--allow-mmio]\n"
            "                         [--sysfs-root=PATH] [--expect-bdf=BDF]\n"
            "      gp107ctl layout\n");
    return GP107_ERR_USAGE;
}

static void print_inventory(const struct gp107_inventory *inv)
{
    printf("((kind . gp107-userspace-capability-identity)\n");
    printf(" (authority . gp107-research-not-abi)\n");
    printf(" (abi-pin . untouched)\n");
    printf(" (pci (vendor . 0x%04x) (device . 0x%04x) (bdf . \"%s\")\n",
           inv->pci.vendor, inv->pci.device, inv->bdf);
    printf("  (bar0-base . 0x%08x) (bar0-size . 0x%08x))\n",
           inv->pci.bar0_base, inv->pci.bar0_size);
    printf(" (driver (bound . %s) (name . \"%s\"))\n",
           inv->driver.bound ? "yes" : "no", inv->driver.name);
    printf(" (rights (pci . inventory-only) (rm-control . none) (mmio . none))\n");
    printf(" (evidence (pci . runtime-proven) (driver . runtime-proven)"
           " (boot0 . unproven))\n");
    printf(" (summary . IDENTITY-OK))\n");
}

static int parse_offset(const char *s, uint32_t *out)
{
    char *end = NULL;
    unsigned long v;

    errno = 0;
    v = strtoul(s, &end, 0);
    if (errno != 0 || end == s || v > 0xffffffffu) {
        return -1;
    }
    while (*end == '\n' || *end == '\r' || *end == ' ') {
        end++;
    }
    if (*end != '\0') {
        return -1;
    }
    *out = (uint32_t)v;
    return 0;
}

int main(int argc, char **argv)
{
    const char *root = GP107_DEFAULT_SYSFS;
    const char *expect = GP107_EXPECTED_BDF;
    const char *mode;
    char err[256];
    struct gp107_inventory inv;
    uint32_t offset = 0;
    uint32_t value = 0;
    int allow = 0;
    int i;
    int rc;

    if (argc < 2) {
        return usage();
    }
    mode = argv[1];
    if (strcmp(mode, "layout") == 0) {
        printf("LAYOUT-OK identity=%zu binding=%zu inventory=%zu\n",
               sizeof(struct gp107_pci_identity),
               sizeof(struct gp107_driver_binding),
               sizeof(struct gp107_inventory));
        return GP107_OK;
    }
    if (strcmp(mode, "inventory") != 0 && strcmp(mode, "mmio-read") != 0) {
        return usage();
    }

    for (i = 2; i < argc; i++) {
        if (strncmp(argv[i], "--sysfs-root=", 13) == 0) {
            root = argv[i] + 13;
        } else if (strncmp(argv[i], "--expect-bdf=", 13) == 0) {
            expect = argv[i] + 13;
        } else if (strncmp(argv[i], "--offset=", 9) == 0) {
            if (parse_offset(argv[i] + 9, &offset) != 0) {
                fprintf(stderr, "USAGE-FAIL step=offset code=%d value=%s\n",
                        GP107_ERR_USAGE, argv[i] + 9);
                return GP107_ERR_USAGE;
            }
        } else if (strcmp(argv[i], "--allow-mmio") == 0) {
            allow = 1;
        } else if (strcmp(argv[i], "--help") == 0) {
            return usage();
        } else {
            fprintf(stderr, "USAGE-FAIL step=unknown-option code=%d value=%s\n",
                    GP107_ERR_USAGE, argv[i]);
            return GP107_ERR_USAGE;
        }
    }

    if (strcmp(mode, "inventory") == 0) {
        rc = gp107_inventory_scan(root, expect, &inv, err, sizeof(err));
        if (rc != GP107_OK) {
            fprintf(stderr, "%s\n", err);
            return rc;
        }
        print_inventory(&inv);
        return GP107_OK;
    }

    rc = gp107_mmio_require_optin(allow, err, sizeof(err));
    if (rc != GP107_OK) {
        fprintf(stderr, "%s\n", err);
        return rc;
    }
    rc = gp107_inventory_scan(root, expect, &inv, err, sizeof(err));
    if (rc != GP107_OK) {
        fprintf(stderr, "%s\n", err);
        return rc;
    }
    rc = gp107_mmio_check_driver(&inv, err, sizeof(err));
    if (rc != GP107_OK) {
        fprintf(stderr, "%s\n", err);
        return rc;
    }
    rc = gp107_mmio_read32(root, inv.bdf, offset, &value, err, sizeof(err));
    if (rc != GP107_OK) {
        fprintf(stderr, "%s\n", err);
        return rc;
    }
    printf("((kind . gp107-mmio-read)\n");
    printf(" (offset . 0x%x) (value . 0x%08x)\n", offset, value);
    printf(" (right . read-only) (evidence . runtime-proven)\n");
    printf(" (boot0 . unproven) (summary . MMIO-READ-OK))\n");
    return GP107_OK;
}
