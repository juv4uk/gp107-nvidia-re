#ifndef GP107_IDENTITY_H
#define GP107_IDENTITY_H

#include <stddef.h>
#include <stdint.h>

/*
 * Clean-room userspace capability identity for GP107 / GTX 1050 Ti.
 *
 * Authority: this C implementation over sysfs only. It is research code,
 * not an ABI, not a kernel driver, and not a claim about register access.
 * SENS, CML, wsm-os-lisp, target contract and ABI pins are untouched.
 *
 * Two sources are kept distinct on purpose:
 *   - sysfs PCI config/vendor/device = inventory fact;
 *   - sysfs driver link             = binding fact.
 * Neither is promoted into a right to touch an aperture.
 */

#define GP107_PCI_VENDOR_NVIDIA 0x10deu
#define GP107_PCI_DEVICE_GP107  0x1c82u
#define GP107_EXPECTED_BDF      "0000:01:00.0"
#define GP107_DEFAULT_SYSFS     "/sys"
#define GP107_CONFIG_BYTES      32u

enum gp107_status {
    GP107_OK               = 0,
    GP107_ERR_OPEN         = 2,
    GP107_ERR_READ         = 3,
    GP107_ERR_PARSE        = 4,
    GP107_ERR_CONFIG       = 5,
    GP107_ERR_NO_MATCH     = 12,
    GP107_ERR_CARD_COUNT   = 13,
    GP107_ERR_BDF          = 14,
    GP107_ERR_OPTIN        = 15,
    GP107_ERR_DRIVER_BOUND = 16,
    GP107_ERR_OFFSET       = 17,
    GP107_ERR_MAP          = 18,
    GP107_ERR_DRIVER_LINK  = 20,
    GP107_ERR_RESOURCE_SIZE = 21,
    GP107_ERR_ALIGNMENT     = 22,
    GP107_ERR_USAGE        = 64
};

enum gp107_evidence {
    GP107_UNPROVEN = 0,
    GP107_STATIC_PROVEN,
    GP107_RUNTIME_PROVEN,
    GP107_STRING_ONLY
};

struct gp107_pci_identity {
    uint16_t vendor;        /* offset  0, config 0x00 */
    uint16_t device;        /* offset  2, config 0x02 */
    uint16_t domain;        /* offset  4, sysfs BDF */
    uint8_t  bus;           /* offset  6, sysfs BDF */
    uint8_t  slot;          /* offset  7, sysfs BDF */
    uint8_t  function;      /* offset  8, sysfs BDF */
    uint8_t  revision;      /* offset  9, config 0x08 */
    uint16_t command;       /* offset 10, config 0x04 */
    uint32_t bar0_raw;      /* offset 12, config 0x10 raw dword */
    uint32_t bar0_base;     /* offset 16, low flag bits masked */
    uint32_t bar0_size;     /* offset 20, from resource0 size when visible */
    uint8_t  class_code[3]; /* offset 24, config 0x09..0x0b */
    uint8_t  header_type;   /* offset 27, config 0x0e */
    uint8_t  bar0_space;    /* offset 28: 0 memory, 1 io */
    uint8_t  bar0_width;    /* offset 29: 0 32-bit, 1 64-bit */
    uint8_t  bar0_prefetch; /* offset 30: 1 when prefetchable */
    uint8_t  cfg_bytes;     /* offset 31: bytes actually decoded */
};

struct gp107_driver_binding {
    char name[64];      /* offset  0 */
    int  bound;         /* offset 64: 1 bound, 0 confirmed-unbound */
};

struct gp107_inventory {
    struct gp107_pci_identity  pci;       /* offset   0 */
    struct gp107_driver_binding driver;   /* offset  20 */
    char bdf[32];                         /* offset  88 */
    int  candidate_count;                 /* offset 120 */
    int  valid_count;                     /* offset 124 */
};

/* Compile-time layout contract: drift must break the build, not silently
 * change what a caller reads out of a returned structure. */
_Static_assert(sizeof(struct gp107_pci_identity) == 32, "pci layout drift");
_Static_assert(sizeof(struct gp107_driver_binding) == 68, "driver layout drift");
_Static_assert(sizeof(struct gp107_inventory) == 140, "inventory layout drift");

int gp107_set_error(char *err, size_t errsz, const char *fmt, ...);

/* Fail closed: exactly one matching card with cross-checked PCI config,
 * expected BDF, and a readable-or-absent driver link. */
int gp107_inventory_scan(const char *sysfs_root, const char *expect_bdf,
                         struct gp107_inventory *out, char *err, size_t errsz);

#endif
