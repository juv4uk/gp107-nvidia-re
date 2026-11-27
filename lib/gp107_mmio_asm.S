/*
 * x86-64 SysV read-only 32-bit load from an already-mapped aperture.
 *
 * Own assembly, clean-room: no vendor instruction sequences, no register
 * constants, no BOOT0 assumption. The caller owns the mapping and the
 * opt-in/driver-unbound gates; this primitive only performs one load.
 *
 * rdi = const volatile void *address
 * eax = little-endian 32-bit word
 */
	.text
	.globl	gp107_mmio_load32_asm
	.hidden	gp107_mmio_load32_asm
	.type	gp107_mmio_load32_asm, @function
gp107_mmio_load32_asm:
	movl	(%rdi), %eax
	lfence
	ret
	.size	gp107_mmio_load32_asm, .-gp107_mmio_load32_asm

	.section	.note.GNU-stack,"",@progbits
