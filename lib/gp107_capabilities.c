#include "gp107_capabilities.h"

#include <stdarg.h>
#include <stdio.h>
#include <string.h>

static void append_line(char *out, size_t cap, const char *fmt, ...)
{
    size_t used = strlen(out);
    va_list ap;
    int n;

    if (used + 1 >= cap) {
        return;
    }
    va_start(ap, fmt);
    n = vsnprintf(out + used, cap - used, fmt, ap);
    va_end(ap);
    if (n < 0) {
        out[used] = '\0';
    }
}

int gp107_capability_report(const struct gp107_inventory *inv,
                            int allow_mmio, char *out, size_t cap)
{
    const char *state;
    const char *reason;

    if (inv == NULL || out == NULL || cap == 0) {
        return GP107_ERR_USAGE;
    }
    out[0] = '\0';

    if (inv->driver.bound) {
        state = "denied";
        reason = "driver-bound";
    } else if (!allow_mmio) {
        state = "deferred";
        reason = "opt-in-required";
    } else {
        state = "granted";
        reason = "read-only-window";
    }

    append_line(out, cap, "((kind . gp107-capability-ledger)\n");
    append_line(out, cap, " (authority . gp107-research-not-abi)\n");
    append_line(out, cap, " (abi-pin . untouched)\n");
    append_line(out, cap, " (pci-inventory . observed)"
                          " (evidence . caller-supplied-sysfs)\n");
    append_line(out, cap, " (bar0-decode . %s)"
                          " (evidence . statically-proven-layout)\n",
                inv->pci.cfg_bytes == GP107_CONFIG_BYTES ? "complete" : "partial");
    append_line(out, cap, " (rm-identity . deferred)"
                          " (reason . not-in-this-slice)\n");
    append_line(out, cap, " (mmio-read-software-gate . %s) (reason . %s)\n", state, reason);
    append_line(out, cap, " (owner-approval . not-inferred)\n");
    append_line(out, cap, " (physical-mmio . not-authorized)\n");
    append_line(out, cap, " (boot0 . unproven) (evidence . unproven)\n");
    append_line(out, cap, " (rights (write . none) (dispatch . none)"
                          " (rm . none))\n");
    append_line(out, cap, " (summary . CAPABILITY-LEDGER-OK))\n");
    return GP107_OK;
}
