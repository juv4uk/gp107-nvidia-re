/*
 * 01_min_cuinit.c -- clean-room cuInit-like device discovery for Pascal GP107.
 *
 * Uses only the public Linux ioctl ABI of /dev/nvidiactl and /dev/nvidiaN.
 * No libcuda.so, no vendor headers, no decompiled code.
 *
 * Verified with driver 580.196.11, kernel 7.2.15+kali-amd64.
 */
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <unistd.h>

#define NV_IOCTL_MAGIC 'F'          /* NV_IOCTL_MAGIC in nv-ioctl-numbers.h */
#define NV_ESC_CARD_INFO   200      /* NV_IOCTL_BASE + 0  */
#define NV_ESC_REGISTER_FD 201      /* NV_IOCTL_BASE + 1  */
#define NV_ESC_SYS_PARAMS  214      /* NV_IOCTL_BASE + 14 */
#define NV_MAX_CARDS       32       /* 2304 bytes / 72-byte entry */

/* ABI layouts reconstructed from the driver's public headers. */
struct nv_pci_info {
    uint32_t domain;
    uint8_t  bus;
    uint8_t  slot;
    uint8_t  function;
    uint16_t vendor_id;
    uint16_t device_id;
};

struct nv_card_info {
    uint32_t          valid;
    struct nv_pci_info pci;
    uint32_t          gpu_id;
    uint16_t          interrupt_line;
    uint64_t          reg_address;
    uint64_t          reg_size;
    uint64_t          fb_address;
    uint64_t          fb_size;
    uint32_t          minor_number;
    uint8_t           dev_name[10];
};

_Static_assert(sizeof(struct nv_pci_info) == 12, "unexpected nv_pci_info ABI");
_Static_assert(sizeof(struct nv_card_info) == 72, "unexpected nv_card_info ABI");

static int fail(const char *what)
{
    fprintf(stderr, "%s: %s\n", what, strerror(errno));
    return 1;
}

/*
 * NV_ESC_SYS_PARAMS is a set-once value: the kernel driver stores the first
 * memblock_size it receives and returns EBUSY for any later, different value.
 * cuInit reads the same sysfs file before issuing the ioctl, so we must too.
 */
static int read_memblock_size(uint64_t *out)
{
    FILE *f = fopen("/sys/devices/system/memory/block_size_bytes", "r");
    if (!f)
        return -1;

    char buf[64] = {0};
    if (!fgets(buf, sizeof(buf), f)) {
        fclose(f);
        return -1;
    }
    fclose(f);

    errno = 0;
    char *end = NULL;
    unsigned long long value = strtoull(buf, &end, 16);
    if (errno || end == buf)
        return -1;

    *out = (uint64_t)value;
    return 0;
}

int main(void)
{
    int ctl = open("/dev/nvidiactl", O_RDWR | O_CLOEXEC);
    if (ctl < 0)
        return fail("open(/dev/nvidiactl)");

    uint64_t memblock_size = 0;
    if (read_memblock_size(&memblock_size) < 0)
        return fail("read(/sys/devices/system/memory/block_size_bytes)");

    printf("sysfs block_size_bytes : %#llx\n",
           (unsigned long long)memblock_size);

    /* Pass the variable itself: _IOWR() applies sizeof() to the 3rd argument. */
    if (ioctl(ctl, _IOWR(NV_IOCTL_MAGIC, NV_ESC_SYS_PARAMS, memblock_size),
              &memblock_size) < 0) {
        fail("ioctl(NV_ESC_SYS_PARAMS)");
        close(ctl);
        return 1;
    }
    printf("NV_ESC_SYS_PARAMS  : memblock_size = %llu bytes\n",
           (unsigned long long)memblock_size);

    struct nv_card_info cards[NV_MAX_CARDS];
    memset(cards, 0, sizeof(cards));
    if (ioctl(ctl, _IOWR(NV_IOCTL_MAGIC, NV_ESC_CARD_INFO, cards), cards) < 0) {
        fail("ioctl(NV_ESC_CARD_INFO)");
        close(ctl);
        return 1;
    }

    unsigned found = 0;
    for (unsigned i = 0; i < NV_MAX_CARDS; i++) {
        const struct nv_card_info *c = &cards[i];
        if (!c->valid)
            continue;
        found++;
        printf("NV_ESC_CARD_INFO   : GPU %u: %04x:%04x @ %04x:%02x:%02x.%d, "
               "gpu_id=%#x, minor=%u, BAR0=%#llx+%#llx, FB=%#llx+%#llx\n",
               i, c->pci.vendor_id, c->pci.device_id,
               c->pci.domain, c->pci.bus, c->pci.slot, c->pci.function,
               c->gpu_id, c->minor_number,
               (unsigned long long)c->reg_address,
               (unsigned long long)c->reg_size,
               (unsigned long long)c->fb_address,
               (unsigned long long)c->fb_size);

        char path[64];
        snprintf(path, sizeof(path), "/dev/nvidia%u", c->minor_number);
        int gpu = open(path, O_RDWR | O_CLOEXEC);
        if (gpu < 0) {
            fail(path);
            continue;
        }
        printf("open(%s)     : fd=%d\n", path, gpu);

        /* cuInit issues this on the GPU fd, passing the control fd as argument. */
        if (ioctl(gpu, _IOWR(NV_IOCTL_MAGIC, NV_ESC_REGISTER_FD, ctl), &ctl) < 0)
            fail("ioctl(NV_ESC_REGISTER_FD)");

        close(gpu);
    }

    if (!found)
        fprintf(stderr, "no valid GPU entries returned\n");

    int uvm = open("/dev/nvidia-uvm", O_RDWR | O_CLOEXEC);
    if (uvm < 0)
        fail("open(/dev/nvidia-uvm)");
    else {
        printf("open(/dev/nvidia-uvm) : fd=%d\n", uvm);
        close(uvm);
    }

    close(ctl);
    return found ? 0 : 2;
}
