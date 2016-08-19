/*
 * Low-level CPU initialisation
 * Based on arch/arm/kernel/head.S
 *
 * Copyright (C) 1994-2002 Russell King
 * Copyright (C) 2003-2012 ARM Ltd.
 * Authors:	Catalin Marinas <catalin.marinas@arm.com>
 *		Will Deacon <will.deacon@arm.com>
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License version 2 as
 * published by the Free Software Foundation.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

#include <linux/linkage.h>
#include <linux/init.h>
#include <linux/irqchip/arm-gic-v3.h>

#include <asm/assembler.h>
#include <asm/boot.h>
#include <asm/ptrace.h>
#include <asm/asm-offsets.h>
#include <asm/cache.h>
#include <asm/cputype.h>
#include <asm/elf.h>
#include <asm/kernel-pgtable.h>
#include <asm/kvm_arm.h>
#include <asm/memory.h>
#include <asm/pgtable-hwdef.h>
#include <asm/pgtable.h>
#include <asm/page.h>
#include <asm/smp.h>
#include <asm/sysreg.h>
#include <asm/thread_info.h>
#include <asm/virt.h>

/** 20160815
 * arch/arm64/Makefile에서
 * CONFIG_ARM64_RANDOMIZE_TEXT_OFFSET면 random offset.
 * 그렇지 않으면 0x8000
 **/
#define __PHYS_OFFSET	(KERNEL_START - TEXT_OFFSET)

#if (TEXT_OFFSET & 0xfff) != 0
#error TEXT_OFFSET must be at least 4KB aligned
#elif (PAGE_OFFSET & 0x1fffff) != 0
#error PAGE_OFFSET must be at least 2MB aligned
#elif TEXT_OFFSET > 0x1fffff
#error TEXT_OFFSET must be less than 2MB
#endif

/*
 * Kernel startup entry point.
 * ---------------------------
 *
 * The requirements are:
 *   MMU = off, D-cache = off, I-cache = on or off,
 *   x0 = physical address to the FDT blob.
 *
 * This code is mostly position independent so you call this at
 * __pa(PAGE_OFFSET + TEXT_OFFSET).
 *
 * Note that the callee-saved registers are used for storing variables
 * that are useful before the MMU is enabled. The allocations are described
 * in the entry routines.
 */
/** 20160814
 * kernel 진입시 요구사항
 *   MMU = off, D-cache = off, I-cache = on or off,
 *   x0 = physical address to the FDT blob.
 *
 * 왜 MMU와 D-cache는 꺼져 있어야 하나요???
 * 참고로 arm 32비트 커널은...
 * are: MMU = off, D-cache = off, I-cache = dont care, r0 = 0,
 * r1 = machine nr, r2 = atags or dtb pointer.
 **/
	__HEAD
_head:
	/*
	 * DO NOT MODIFY. Image header expected by Linux boot-loaders.
	 */
#ifdef CONFIG_EFI
	/*
	 * This add instruction has no meaningful effect except that
	 * its opcode forms the magic "MZ" signature required by UEFI.
	 */
	add	x13, x18, #0x16
	b	stext
#else
	/** 20160814
	 * EFI가 아닌 경우 stext로 branch.
	 **/
	b	stext				// branch to kernel start, magic
	.long	0				// reserved
#endif
	le64sym	_kernel_offset_le		// Image load offset from start of RAM, little-endian
	le64sym	_kernel_size_le			// Effective size of kernel image, little-endian
	le64sym	_kernel_flags_le		// Informative flags, little-endian
	.quad	0				// reserved
	.quad	0				// reserved
	.quad	0				// reserved
	.byte	0x41				// Magic number, "ARM\x64"
	.byte	0x52
	.byte	0x4d
	.byte	0x64
#ifdef CONFIG_EFI
	.long	pe_header - _head		// Offset to the PE header.
#else
	.word	0				// reserved
#endif

#ifdef CONFIG_EFI
	.align 3
pe_header:
	.ascii	"PE"
	.short 	0
coff_header:
	.short	0xaa64				// AArch64
	.short	2				// nr_sections
	.long	0 				// TimeDateStamp
	.long	0				// PointerToSymbolTable
	.long	1				// NumberOfSymbols
	.short	section_table - optional_header	// SizeOfOptionalHeader
	.short	0x206				// Characteristics.
						// IMAGE_FILE_DEBUG_STRIPPED |
						// IMAGE_FILE_EXECUTABLE_IMAGE |
						// IMAGE_FILE_LINE_NUMS_STRIPPED
optional_header:
	.short	0x20b				// PE32+ format
	.byte	0x02				// MajorLinkerVersion
	.byte	0x14				// MinorLinkerVersion
	.long	_end - efi_header_end		// SizeOfCode
	.long	0				// SizeOfInitializedData
	.long	0				// SizeOfUninitializedData
	.long	__efistub_entry - _head		// AddressOfEntryPoint
	.long	efi_header_end - _head		// BaseOfCode

extra_header_fields:
	.quad	0				// ImageBase
	.long	0x1000				// SectionAlignment
	.long	PECOFF_FILE_ALIGNMENT		// FileAlignment
	.short	0				// MajorOperatingSystemVersion
	.short	0				// MinorOperatingSystemVersion
	.short	0				// MajorImageVersion
	.short	0				// MinorImageVersion
	.short	0				// MajorSubsystemVersion
	.short	0				// MinorSubsystemVersion
	.long	0				// Win32VersionValue

	.long	_end - _head			// SizeOfImage

	// Everything before the kernel image is considered part of the header
	.long	efi_header_end - _head		// SizeOfHeaders
	.long	0				// CheckSum
	.short	0xa				// Subsystem (EFI application)
	.short	0				// DllCharacteristics
	.quad	0				// SizeOfStackReserve
	.quad	0				// SizeOfStackCommit
	.quad	0				// SizeOfHeapReserve
	.quad	0				// SizeOfHeapCommit
	.long	0				// LoaderFlags
	.long	0x6				// NumberOfRvaAndSizes

	.quad	0				// ExportTable
	.quad	0				// ImportTable
	.quad	0				// ResourceTable
	.quad	0				// ExceptionTable
	.quad	0				// CertificationTable
	.quad	0				// BaseRelocationTable

	// Section table
section_table:

	/*
	 * The EFI application loader requires a relocation section
	 * because EFI applications must be relocatable.  This is a
	 * dummy section as far as we are concerned.
	 */
	.ascii	".reloc"
	.byte	0
	.byte	0			// end of 0 padding of section name
	.long	0
	.long	0
	.long	0			// SizeOfRawData
	.long	0			// PointerToRawData
	.long	0			// PointerToRelocations
	.long	0			// PointerToLineNumbers
	.short	0			// NumberOfRelocations
	.short	0			// NumberOfLineNumbers
	.long	0x42100040		// Characteristics (section flags)


	.ascii	".text"
	.byte	0
	.byte	0
	.byte	0        		// end of 0 padding of section name
	.long	_end - efi_header_end	// VirtualSize
	.long	efi_header_end - _head	// VirtualAddress
	.long	_edata - efi_header_end	// SizeOfRawData
	.long	efi_header_end - _head	// PointerToRawData

	.long	0		// PointerToRelocations (0 for executables)
	.long	0		// PointerToLineNumbers (0 for executables)
	.short	0		// NumberOfRelocations  (0 for executables)
	.short	0		// NumberOfLineNumbers  (0 for executables)
	.long	0xe0500020	// Characteristics (section flags)

	/*
	 * EFI will load .text onwards at the 4k section alignment
	 * described in the PE/COFF header. To ensure that instruction
	 * sequences using an adrp and a :lo12: immediate will function
	 * correctly at this alignment, we must ensure that .text is
	 * placed at a 4k boundary in the Image to begin with.
	 */
	.align 12
efi_header_end:
#endif

	__INIT

ENTRY(stext)
	bl	preserve_boot_args
	bl	el2_setup			// Drop to EL1, w20=cpu_boot_mode
	/** 20160815
	 * __PHYS_OFFSET은 random값으로 설정될 수 있음.
	 * KASLR align을 x23에 저장.
	 * KASLR : Kernel address space layout randomization
	 * https://lwn.net/Articles/569635/
	 * http://selinuxproject.org/~jmorris/lss2013_slides/cook_kaslr.pdf
	 **/
	adrp	x24, __PHYS_OFFSET
	and	x23, x24, MIN_KIMG_ALIGN - 1	// KASLR offset, defaults to 0
	bl	set_cpu_boot_mode_flag
	bl	__create_page_tables		// x25=TTBR0, x26=TTBR1
	/*
	 * The following calls CPU setup code, see arch/arm64/mm/proc.S for
	 * details.
	 * On return, the CPU will be ready for the MMU to be turned on and
	 * the TCR will have been set.
	 */
	bl	__cpu_setup			// initialise processor
	adr_l	x27, __primary_switch		// address to jump to after
						// MMU has been enabled
	b	__enable_mmu
ENDPROC(stext)

/*
 * Preserve the arguments passed by the bootloader in x0 .. x3
 */
preserve_boot_args:
	/** 20160814
	 * FDT physical address 복사
	 **/
	mov	x21, x0				// x21=FDT

	/** 20160814
	 * boot_args 심볼의 pc-relative  주소를 x0에 저장.
	 * x21과 x1을 x0가 가리키는 주소에 저장한다.
	 *
	 * booting.txt를 보면 x0에 dtb 주소만 저장하기로 약속되어 있다.
	 * 왜 여기서 x0, x1, x2, x3를 부트로더에서 전달해준 주소라고
	 * 따로 저장하나???
	 **/
	adr_l	x0, boot_args			// record the contents of
	stp	x21, x1, [x0]			// x0 .. x3 at kernel entry
	stp	x2, x3, [x0, #16]

	/** 20160814
	 * cache range를 invalidate 하기 전에 memory barrier를 둔다.
	 *
	 * 궁금증
	 *  1. MMU off 상태에서 dc ivac이 무슨 의미가 있나???
	 *  2. cache를 invalid 시킨다면 dsb가 필요한 게 아닌가?
	 *     dmb로만 충분한가???
	 **/
	dmb	sy				// needed before dc ivac with
						// MMU off

	/** 20160814
	 * cache invalidate 시킬 메모리 영역은 boot_args를 저장한 위치.
	 **/
	add	x1, x0, #0x20			// 4 x 8 bytes
	b	__inval_cache_range		// tail call
ENDPROC(preserve_boot_args)

/*
 * Macro to create a table entry to the next page.
 *
 *	tbl:	page table address
 *	virt:	virtual address
 *	shift:	#imm page table shift
 *	ptrs:	#imm pointers per table page
 *
 * Preserves:	virt
 * Corrupts:	tmp1, tmp2
 * Returns:	tbl -> next level table page address
 */
	.macro	create_table_entry, tbl, virt, shift, ptrs, tmp1, tmp2
	lsr	\tmp1, \virt, #\shift
	and	\tmp1, \tmp1, #\ptrs - 1	// table index
	add	\tmp2, \tbl, #PAGE_SIZE
	orr	\tmp2, \tmp2, #PMD_TYPE_TABLE	// address of next table and entry type
	str	\tmp2, [\tbl, \tmp1, lsl #3]
	add	\tbl, \tbl, #PAGE_SIZE		// next level table page
	.endm

/*
 * Macro to populate the PGD (and possibily PUD) for the corresponding
 * block entry in the next level (tbl) for the given virtual address.
 *
 * Preserves:	tbl, next, virt
 * Corrupts:	tmp1, tmp2
 */
	.macro	create_pgd_entry, tbl, virt, tmp1, tmp2
	create_table_entry \tbl, \virt, PGDIR_SHIFT, PTRS_PER_PGD, \tmp1, \tmp2
#if SWAPPER_PGTABLE_LEVELS > 3
	create_table_entry \tbl, \virt, PUD_SHIFT, PTRS_PER_PUD, \tmp1, \tmp2
#endif
#if SWAPPER_PGTABLE_LEVELS > 2
	create_table_entry \tbl, \virt, SWAPPER_TABLE_SHIFT, PTRS_PER_PTE, \tmp1, \tmp2
#endif
	.endm

/*
 * Macro to populate block entries in the page table for the start..end
 * virtual range (inclusive).
 *
 * Preserves:	tbl, flags
 * Corrupts:	phys, start, end, pstate
 */
	.macro	create_block_map, tbl, flags, phys, start, end
	lsr	\phys, \phys, #SWAPPER_BLOCK_SHIFT
	lsr	\start, \start, #SWAPPER_BLOCK_SHIFT
	and	\start, \start, #PTRS_PER_PTE - 1	// table index
	orr	\phys, \flags, \phys, lsl #SWAPPER_BLOCK_SHIFT	// table entry
	lsr	\end, \end, #SWAPPER_BLOCK_SHIFT
	and	\end, \end, #PTRS_PER_PTE - 1		// table end index
9999:	str	\phys, [\tbl, \start, lsl #3]		// store the entry
	add	\start, \start, #1			// next entry
	add	\phys, \phys, #SWAPPER_BLOCK_SIZE		// next block
	cmp	\start, \end
	b.ls	9999b
	.endm

/*
 * Setup the initial page tables. We only setup the barest amount which is
 * required to get the kernel running. The following sections are required:
 *   - identity mapping to enable the MMU (low address, TTBR0)
 *   - first few MB of the kernel linear mapping to jump to once the MMU has
 *     been enabled
 */
__create_page_tables:
	adrp	x25, idmap_pg_dir
	adrp	x26, swapper_pg_dir
	mov	x28, lr

	/*
	 * Invalidate the idmap and swapper page tables to avoid potential
	 * dirty cache lines being evicted.
	 */
	mov	x0, x25
	add	x1, x26, #SWAPPER_DIR_SIZE
	bl	__inval_cache_range

	/*
	 * Clear the idmap and swapper page tables.
	 */
	mov	x0, x25
	add	x6, x26, #SWAPPER_DIR_SIZE
1:	stp	xzr, xzr, [x0], #16
	stp	xzr, xzr, [x0], #16
	stp	xzr, xzr, [x0], #16
	stp	xzr, xzr, [x0], #16
	cmp	x0, x6
	b.lo	1b

	mov	x7, SWAPPER_MM_MMUFLAGS

	/*
	 * Create the identity mapping.
	 */
	mov	x0, x25				// idmap_pg_dir
	adrp	x3, __idmap_text_start		// __pa(__idmap_text_start)

#ifndef CONFIG_ARM64_VA_BITS_48
#define EXTRA_SHIFT	(PGDIR_SHIFT + PAGE_SHIFT - 3)
#define EXTRA_PTRS	(1 << (48 - EXTRA_SHIFT))

	/*
	 * If VA_BITS < 48, it may be too small to allow for an ID mapping to be
	 * created that covers system RAM if that is located sufficiently high
	 * in the physical address space. So for the ID map, use an extended
	 * virtual range in that case, by configuring an additional translation
	 * level.
	 * First, we have to verify our assumption that the current value of
	 * VA_BITS was chosen such that all translation levels are fully
	 * utilised, and that lowering T0SZ will always result in an additional
	 * translation level to be configured.
	 */
#if VA_BITS != EXTRA_SHIFT
#error "Mismatch between VA_BITS and page size/number of translation levels"
#endif

	/*
	 * Calculate the maximum allowed value for TCR_EL1.T0SZ so that the
	 * entire ID map region can be mapped. As T0SZ == (64 - #bits used),
	 * this number conveniently equals the number of leading zeroes in
	 * the physical address of __idmap_text_end.
	 */
	adrp	x5, __idmap_text_end
	clz	x5, x5
	cmp	x5, TCR_T0SZ(VA_BITS)	// default T0SZ small enough?
	b.ge	1f			// .. then skip additional level

	adr_l	x6, idmap_t0sz
	str	x5, [x6]
	dmb	sy
	dc	ivac, x6		// Invalidate potentially stale cache line

	create_table_entry x0, x3, EXTRA_SHIFT, EXTRA_PTRS, x5, x6
1:
#endif

	create_pgd_entry x0, x3, x5, x6
	mov	x5, x3				// __pa(__idmap_text_start)
	adr_l	x6, __idmap_text_end		// __pa(__idmap_text_end)
	create_block_map x0, x7, x3, x5, x6

	/*
	 * Map the kernel image (starting with PHYS_OFFSET).
	 */
	mov	x0, x26				// swapper_pg_dir
	mov_q	x5, KIMAGE_VADDR + TEXT_OFFSET	// compile time __va(_text)
	add	x5, x5, x23			// add KASLR displacement
	create_pgd_entry x0, x5, x3, x6
	adrp	x6, _end			// runtime __pa(_end)
	adrp	x3, _text			// runtime __pa(_text)
	sub	x6, x6, x3			// _end - _text
	add	x6, x6, x5			// runtime __va(_end)
	create_block_map x0, x7, x3, x5, x6

	/*
	 * Since the page tables have been populated with non-cacheable
	 * accesses (MMU disabled), invalidate the idmap and swapper page
	 * tables again to remove any speculatively loaded cache lines.
	 */
	mov	x0, x25
	add	x1, x26, #SWAPPER_DIR_SIZE
	dmb	sy
	bl	__inval_cache_range

	ret	x28
ENDPROC(__create_page_tables)
	.ltorg

/*
 * The following fragment of code is executed with the MMU enabled.
 */
	.set	initial_sp, init_thread_union + THREAD_START_SP
__primary_switched:
	mov	x28, lr				// preserve LR
	adr_l	x8, vectors			// load VBAR_EL1 with virtual
	msr	vbar_el1, x8			// vector table address
	isb

	// Clear BSS
	adr_l	x0, __bss_start
	mov	x1, xzr
	adr_l	x2, __bss_stop
	sub	x2, x2, x0
	bl	__pi_memset
	dsb	ishst				// Make zero page visible to PTW

	adr_l	sp, initial_sp, x4
	mov	x4, sp
	and	x4, x4, #~(THREAD_SIZE - 1)
	msr	sp_el0, x4			// Save thread_info
	str_l	x21, __fdt_pointer, x5		// Save FDT pointer

	ldr_l	x4, kimage_vaddr		// Save the offset between
	sub	x4, x4, x24			// the kernel virtual and
	str_l	x4, kimage_voffset, x5		// physical mappings

	mov	x29, #0
#ifdef CONFIG_KASAN
	bl	kasan_early_init
#endif
#ifdef CONFIG_RANDOMIZE_BASE
	tst	x23, ~(MIN_KIMG_ALIGN - 1)	// already running randomized?
	b.ne	0f
	mov	x0, x21				// pass FDT address in x0
	mov	x1, x23				// pass modulo offset in x1
	bl	kaslr_early_init		// parse FDT for KASLR options
	cbz	x0, 0f				// KASLR disabled? just proceed
	orr	x23, x23, x0			// record KASLR offset
	ret	x28				// we must enable KASLR, return
						// to __enable_mmu()
0:
#endif
	b	start_kernel
ENDPROC(__primary_switched)

/*
 * end early head section, begin head code that is also used for
 * hotplug and needs to have the same protections as the text region
 */
	.section ".text","ax"

ENTRY(kimage_vaddr)
	.quad		_text - TEXT_OFFSET

/*
 * If we're fortunate enough to boot at EL2, ensure that the world is
 * sane before dropping to EL1.
 *
 * Returns either BOOT_CPU_MODE_EL1 or BOOT_CPU_MODE_EL2 in x20 if
 * booted in EL1 or EL2 respectively.
 */
ENTRY(el2_setup)
	/** 20160815
	 * if (CurrentEL == EL2)
	 *   mrs x0, sctlr_el2		// System Control Register EL2
	 *   ...
	 * else
	 *   mrs, x0, sctlr_el1		// System Control Register EL1
	 *   ...
	 *   mov	w20, #BOOT_CPU_MODE_EL1		// This cpu booted in EL1
	 *   ret
	 **/
	mrs	x0, CurrentEL
	cmp	x0, #CurrentEL_EL2
	b.ne	1f
	/** 20160815
	 * EE : Exception Endianness
	 *   0	Littel-Endian
	 *   1  Big-Endian
	 * the value of the CPSR.E bit on entry to an exception vector,
	 * including reset.
	 * This value also indicates the endianness of the
	 * translation table data for translation table lookups. 
	 **/
	mrs	x0, sctlr_el2
CPU_BE(	orr	x0, x0, #(1 << 25)	)	// Set the EE bit for EL2
CPU_LE(	bic	x0, x0, #(1 << 25)	)	// Clear the EE bit for EL2
	msr	sctlr_el2, x0
	b	2f
1:	mrs	x0, sctlr_el1
CPU_BE(	orr	x0, x0, #(3 << 24)	)	// Set the EE and E0E bits for EL1
CPU_LE(	bic	x0, x0, #(3 << 24)	)	// Clear the EE and E0E bits for EL1
	msr	sctlr_el1, x0
	/** 20160815
	 * w20에 EL1에서 부팅했음을 저장
	 **/
	mov	w20, #BOOT_CPU_MODE_EL1		// This cpu booted in EL1
	isb
	ret

2:
/** 20160815
 * VHE : Virtualization Host Extensions
 * feature가 지원된다면 kernel이 EL2에서 동작하도록 해서
 * KVM 같은 경우 world switch 를 줄여준다.
 **/
#ifdef CONFIG_ARM64_VHE
	/*
	 * Check for VHE being present. For the rest of the EL2 setup,
	 * x2 being non-zero indicates that we do have VHE, and that the
	 * kernel is intended to run at EL2.
	 */
	/** 20160815
	 * 아래 레지스터에 대한 세팅 :  DDI0557A_b_armv8_1_supplement
	 * id_aa64mmfr1 :  AArch64 Memory Model Feature Register 1
	 * ubfx         :  Unsigned bitfield extract
	 *     UBFX <Xd>, <Xn>, #<lsb>, #<width>
	 **/
	mrs	x2, id_aa64mmfr1_el1
	ubfx	x2, x2, #8, #4
#else
	mov	x2, xzr
#endif

	/* Hyp configuration. */
	/** 20160815
	 * EL2에서 host OS가 동작하도록 설정한다.
	 *
	 * cbz : Compare and Branch on Zero 
	 * HCR_TGE : Trap General Exceptions, from Non-secure EL0.
	 *   EL1의 exception을 EL2로 보낸다.
	 * HCR_E2H : Enables a Host Operating System is running in EL2
	 *   HOST OS가 EL2에서 동작하도록 한다.
	 **/
	mov	x0, #HCR_RW			// 64-bit EL1
	cbz	x2, set_hcr
	orr	x0, x0, #HCR_TGE		// Enable Host Extensions
	orr	x0, x0, #HCR_E2H
set_hcr:
	msr	hcr_el2, x0
	isb

	/* Generic timers. */
	/** 20160815
	 * cnthctl_el2 : Counter-timer Hypervisor Control register
	 *   Traps Non-secure EL0 and EL1 accesses to the
	 *   physical counter register to EL2.
	 *
	 *   해당 비트를 1로 세팅해 trap을 발생시키지 않는다.
	 **/
	mrs	x0, cnthctl_el2
	orr	x0, x0, #3			// Enable EL1 physical timers
	msr	cnthctl_el2, x0
	/** 20160815
	 * offset between the physical count value visible in CNTPCT_EL0
	 * and the virtual count value visible in CNTVCT_EL0.
	 **/
	msr	cntvoff_el2, xzr		// Clear virtual offset

#ifdef CONFIG_ARM_GIC_V3
	/* GICv3 system register access */
	/** 20160815
	 * 해당 비트의 의미는
	 * System register interface to versions 3.0 and 4.0
	 * of the GIC CPU interface is supported.
	 * 지원시 GICv3를 설정한다.
	 **/
	mrs	x0, id_aa64pfr0_el1
	ubfx	x0, x0, #24, #4
	cmp	x0, #1
	b.ne	3f

	/** 20160815
	 * ICC_SRE_EL2 : Interrupt Controller Hyp System Register Enable register
	 * 
	 *   각 비트의 의미는???
	 **/
	mrs_s	x0, ICC_SRE_EL2
	orr	x0, x0, #ICC_SRE_EL2_SRE	// Set ICC_SRE_EL2.SRE==1
	orr	x0, x0, #ICC_SRE_EL2_ENABLE	// Set ICC_SRE_EL2.Enable==1
	msr_s	ICC_SRE_EL2, x0
	isb					// Make sure SRE is now set
	mrs_s	x0, ICC_SRE_EL2			// Read SRE back,
	/** 20160815
	 * TBZ Rt, bit, label // Test and branch if Rt<bit> zero
	 **/
	tbz	x0, #0, 3f			// and check that it sticks
	/** 20160815
	 * Interrupt Controller Hyp Control Register
	 **/
	msr_s	ICH_HCR_EL2, xzr		// Reset ICC_HCR_EL2 to defaults

3:
#endif

	/* Populate ID registers. */
	/** 20160815
	 * 실제 ID를 읽어 대응하는 virtualization에 저장한다.
	 * midr_el1 : Main ID Register. implement, revision 정보 등
	 * mpidr_el1 : Multiprocessor Affinity Register
	 * vpidr_el2 : Virtualization Processor ID Register
	 * vmpidr_el2 : Virtualization Multiprocessor ID Register
	 **/
	mrs	x0, midr_el1
	mrs	x1, mpidr_el1
	msr	vpidr_el2, x0
	msr	vmpidr_el2, x1

	/*
	 * When VHE is not in use, early init of EL2 and EL1 needs to be
	 * done here.
	 * When VHE _is_ in use, EL1 will not be used in the host and
	 * requires no configuration, and all non-hyp-specific EL2 setup
	 * will be done via the _EL1 system register aliases in __cpu_setup.
	 */
	/** 20160815
	 * cbnz : Compare and Branch on Nonzero
	 * VHE를 사용하는 경우 x2에는 0이 아닌 값이 들어 있어 1로 점프.
	 * 그렇지 않을 경우 여기에서 sctlr과 cptr 설정.
	 **/
	cbnz	x2, 1f

	/* sctlr_el1 */
	/** 20160815
	 * movk : (0x33d0) << 16 | 0x0800
	 *
	 * sctlr_el1의 endianess 설정
	 * EE : Endianness of data accesses at EL1, and stage 1
	 *      translation table walks in the EL1&0 translation regime.
	 * E0E :  Endianness of data accesses at EL0.
	 **/
	mov	x0, #0x0800			// Set/clear RES{1,0} bits
CPU_BE(	movk	x0, #0x33d0, lsl #16	)	// Set EE and E0E on BE systems
CPU_LE(	movk	x0, #0x30d0, lsl #16	)	// Clear EE and E0E on LE systems
	msr	sctlr_el1, x0

	/* Coprocessor traps. */
	mov	x0, #0x33ff
	/** 20160815
	 * cptr : Architectural Feature Trap Register
	 * coprocessor 접근시 EL2로 trap이 발생하지 않도록 한다.
	 **/
	msr	cptr_el2, x0			// Disable copro. traps to EL2
1:

	/** 20160815
	 * COMPAT : Kernel support for 32-bit EL0
	 *
	 * hstr_el2 : Controls trapping to Hyp mode of Non-secure
	 *            accesses, at EL1 or lower in AArch32, 
	 * cp15의 CRn에 접근시 EL2로 Trap을 발생시키지 않도록 설정한다.
	 **/
#ifdef CONFIG_COMPAT
	msr	hstr_el2, xzr			// Disable CP15 traps to EL2
#endif

	/* EL2 debug */
	/** 20160815
	 * id_aa64dfr0 : AArch64 Debug Feature Register 0
	 * pmcr_el0 : Performance Monitors Control Register
	 * mdcr_el2 : Monitor Debug Configuration Register (EL2)
	 * sbfx : Signed Bit Field Extract (추출한 비트들을 32비트로 sign extend)
	 *
	 * PMU version을 읽어와 no PMU present인 경우 skip.
	 * 버전이 있으면 EL1에서 debug 접근시 trap이 발생하지 않게 설정
	 *   Defines the number of Performance Monitors counters that are accessible from Non-secure EL0 and EL1 modes.
	 **/
	mrs	x0, id_aa64dfr0_el1		// Check ID_AA64DFR0_EL1 PMUVer
	sbfx	x0, x0, #8, #4
	cmp	x0, #1
	b.lt	4f				// Skip if no PMU present
	mrs	x0, pmcr_el0			// Disable debug access traps
	ubfx	x0, x0, #11, #5			// to EL2 and allow access to
	msr	mdcr_el2, x0			// all PMU counters from EL1
4:

	/* Stage-2 translation */
	/** 20160815
	 * vttbr_el2 : Virtualization Translation Table Base Register
	 **/
	msr	vttbr_el2, xzr

	/** 20160815
	 * VHE가 아니면 아래 내용을 skip하고 install_el2_stub으로 점프.
	 **/
	cbz	x2, install_el2_stub

	/** 20160815
	 * w20에 EL2에서 부팅되었음을 기록하고 리턴.
	 **/
	mov	w20, #BOOT_CPU_MODE_EL2		// This CPU booted in EL2
	isb
	ret

	/** 20160815
	 * VHE가 아닌 경우 진행.
	 **/
install_el2_stub:
	/** 20160815
	 * arch/arm64/kernel/hyp-stub.S의 hypervisor stub vectors.
	 *
	 * vbar : Vector Base Address Register 
	 * hypervisor용 exception vector 주소를 쓴다.
	 **/
	/* Hypervisor stub */
	adrp	x0, __hyp_stub_vectors
	add	x0, x0, #:lo12:__hyp_stub_vectors
	msr	vbar_el2, x0

	/* spsr */
	/** 20160815
	 * exception 발생이 EL1h (h는 해당 EL의 stack 사용)에서 발생한
	 * 것으로 설정한 뒤, eret시 EL1에서 수행되도록 한다.
	 * 복귀주소는 stext에서 el2_setup을 호출한 다음 위치이다.
	 * w20에 EL2에서 부팅되었음을 기록한다.
	 **/
	mov	x0, #(PSR_F_BIT | PSR_I_BIT | PSR_A_BIT | PSR_D_BIT |\
		      PSR_MODE_EL1h)
	msr	spsr_el2, x0
	msr	elr_el2, lr
	mov	w20, #BOOT_CPU_MODE_EL2		// This CPU booted in EL2
	eret
ENDPROC(el2_setup)

/*
 * Sets the __boot_cpu_mode flag depending on the CPU boot mode passed
 * in x20. See arch/arm64/include/asm/virt.h for more info.
 */
set_cpu_boot_mode_flag:
	/** 20160815
	 * w20에 저장해둔 BOOT CPU MODE를 읽어 __boot_cpu_mode에 저장.
	 * 메모리 쓰기 명령의 동기화를 위해 dmb 후 cache invalidate.
	 **/
	adr_l	x1, __boot_cpu_mode
	cmp	w20, #BOOT_CPU_MODE_EL2
	b.ne	1f
	add	x1, x1, #4
1:	str	w20, [x1]			// This CPU has booted in EL1
	dmb	sy
	/** 20160815
	 * dc ivac : Data or unified Cache line Invalidate by VA to PoC
	 **/
	dc	ivac, x1			// Invalidate potentially stale cache line
	ret
ENDPROC(set_cpu_boot_mode_flag)

/*
 * We need to find out the CPU boot mode long after boot, so we need to
 * store it in a writable variable.
 *
 * This is not in .bss, because we set it sufficiently early that the boot-time
 * zeroing of .bss would clobber it.
 */
/** 20160815
 * set_cpu_boot_mode_flag에서 해당 위치에 값을 저장
 **/
	.pushsection	.data..cacheline_aligned
	.align	L1_CACHE_SHIFT
ENTRY(__boot_cpu_mode)
	.long	BOOT_CPU_MODE_EL2
	.long	BOOT_CPU_MODE_EL1
	.popsection

	/*
	 * This provides a "holding pen" for platforms to hold all secondary
	 * cores are held until we're ready for them to initialise.
	 */
ENTRY(secondary_holding_pen)
	bl	el2_setup			// Drop to EL1, w20=cpu_boot_mode
	bl	set_cpu_boot_mode_flag
	mrs	x0, mpidr_el1
	mov_q	x1, MPIDR_HWID_BITMASK
	and	x0, x0, x1
	adr_l	x3, secondary_holding_pen_release
pen:	ldr	x4, [x3]
	cmp	x4, x0
	b.eq	secondary_startup
	wfe
	b	pen
ENDPROC(secondary_holding_pen)

	/*
	 * Secondary entry point that jumps straight into the kernel. Only to
	 * be used where CPUs are brought online dynamically by the kernel.
	 */
ENTRY(secondary_entry)
	bl	el2_setup			// Drop to EL1
	bl	set_cpu_boot_mode_flag
	b	secondary_startup
ENDPROC(secondary_entry)

secondary_startup:
	/*
	 * Common entry point for secondary CPUs.
	 */
	adrp	x25, idmap_pg_dir
	adrp	x26, swapper_pg_dir
	bl	__cpu_setup			// initialise processor

	adr_l	x27, __secondary_switch		// address to jump to after enabling the MMU
	b	__enable_mmu
ENDPROC(secondary_startup)

__secondary_switched:
	adr_l	x5, vectors
	msr	vbar_el1, x5
	isb

	adr_l	x0, secondary_data
	ldr	x0, [x0, #CPU_BOOT_STACK]	// get secondary_data.stack
	mov	sp, x0
	and	x0, x0, #~(THREAD_SIZE - 1)
	msr	sp_el0, x0			// save thread_info
	mov	x29, #0
	b	secondary_start_kernel
ENDPROC(__secondary_switched)

/*
 * The booting CPU updates the failed status @__early_cpu_boot_status,
 * with MMU turned off.
 *
 * update_early_cpu_boot_status tmp, status
 *  - Corrupts tmp1, tmp2
 *  - Writes 'status' to __early_cpu_boot_status and makes sure
 *    it is committed to memory.
 */

	.macro	update_early_cpu_boot_status status, tmp1, tmp2
	mov	\tmp2, #\status
	adr_l	\tmp1, __early_cpu_boot_status
	str	\tmp2, [\tmp1]
	dmb	sy
	dc	ivac, \tmp1			// Invalidate potentially stale cache line
	.endm

	.pushsection	.data..cacheline_aligned
	.align	L1_CACHE_SHIFT
ENTRY(__early_cpu_boot_status)
	.long 	0
	.popsection

/*
 * Enable the MMU.
 *
 *  x0  = SCTLR_EL1 value for turning on the MMU.
 *  x27 = *virtual* address to jump to upon completion
 *
 * Other registers depend on the function called upon completion.
 *
 * Checks if the selected granule size is supported by the CPU.
 * If it isn't, park the CPU
 */
	.section	".idmap.text", "ax"
ENTRY(__enable_mmu)
	mrs	x22, sctlr_el1			// preserve old SCTLR_EL1 value
	mrs	x1, ID_AA64MMFR0_EL1
	ubfx	x2, x1, #ID_AA64MMFR0_TGRAN_SHIFT, 4
	cmp	x2, #ID_AA64MMFR0_TGRAN_SUPPORTED
	b.ne	__no_granule_support
	update_early_cpu_boot_status 0, x1, x2
	msr	ttbr0_el1, x25			// load TTBR0
	msr	ttbr1_el1, x26			// load TTBR1
	isb
	msr	sctlr_el1, x0
	isb
	/*
	 * Invalidate the local I-cache so that any instructions fetched
	 * speculatively from the PoC are discarded, since they may have
	 * been dynamically patched at the PoU.
	 */
	ic	iallu
	dsb	nsh
	isb
#ifdef CONFIG_RANDOMIZE_BASE
	mov	x19, x0				// preserve new SCTLR_EL1 value
	blr	x27

	/*
	 * If we return here, we have a KASLR displacement in x23 which we need
	 * to take into account by discarding the current kernel mapping and
	 * creating a new one.
	 */
	msr	sctlr_el1, x22			// disable the MMU
	isb
	bl	__create_page_tables		// recreate kernel mapping

	msr	sctlr_el1, x19			// re-enable the MMU
	isb
	ic	iallu				// flush instructions fetched
	dsb	nsh				// via old mapping
	isb
#endif
	br	x27
ENDPROC(__enable_mmu)

__no_granule_support:
	/* Indicate that this CPU can't boot and is stuck in the kernel */
	update_early_cpu_boot_status CPU_STUCK_IN_KERNEL, x1, x2
1:
	wfe
	wfi
	b 1b
ENDPROC(__no_granule_support)

__primary_switch:
#ifdef CONFIG_RELOCATABLE
	/*
	 * Iterate over each entry in the relocation table, and apply the
	 * relocations in place.
	 */
	ldr	w8, =__dynsym_offset		// offset to symbol table
	ldr	w9, =__rela_offset		// offset to reloc table
	ldr	w10, =__rela_size		// size of reloc table

	mov_q	x11, KIMAGE_VADDR		// default virtual offset
	add	x11, x11, x23			// actual virtual offset
	add	x8, x8, x11			// __va(.dynsym)
	add	x9, x9, x11			// __va(.rela)
	add	x10, x9, x10			// __va(.rela) + sizeof(.rela)

0:	cmp	x9, x10
	b.hs	2f
	ldp	x11, x12, [x9], #24
	ldr	x13, [x9, #-8]
	cmp	w12, #R_AARCH64_RELATIVE
	b.ne	1f
	add	x13, x13, x23			// relocate
	str	x13, [x11, x23]
	b	0b

1:	cmp	w12, #R_AARCH64_ABS64
	b.ne	0b
	add	x12, x12, x12, lsl #1		// symtab offset: 24x top word
	add	x12, x8, x12, lsr #(32 - 3)	// ... shifted into bottom word
	ldrsh	w14, [x12, #6]			// Elf64_Sym::st_shndx
	ldr	x15, [x12, #8]			// Elf64_Sym::st_value
	cmp	w14, #-0xf			// SHN_ABS (0xfff1) ?
	add	x14, x15, x23			// relocate
	csel	x15, x14, x15, ne
	add	x15, x13, x15
	str	x15, [x11, x23]
	b	0b

2:
#endif
	ldr	x8, =__primary_switched
	br	x8
ENDPROC(__primary_switch)

__secondary_switch:
	ldr	x8, =__secondary_switched
	br	x8
ENDPROC(__secondary_switch)
