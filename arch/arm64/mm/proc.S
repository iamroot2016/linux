/*
 * Based on arch/arm/mm/proc.S
 *
 * Copyright (C) 2001 Deep Blue Solutions Ltd.
 * Copyright (C) 2012 ARM Ltd.
 * Author: Catalin Marinas <catalin.marinas@arm.com>
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

#include <linux/init.h>
#include <linux/linkage.h>
#include <asm/assembler.h>
#include <asm/asm-offsets.h>
#include <asm/hwcap.h>
#include <asm/pgtable.h>
#include <asm/pgtable-hwdef.h>
#include <asm/cpufeature.h>
#include <asm/alternative.h>

#ifdef CONFIG_ARM64_64K_PAGES
#define TCR_TG_FLAGS	TCR_TG0_64K | TCR_TG1_64K
#elif defined(CONFIG_ARM64_16K_PAGES)
#define TCR_TG_FLAGS	TCR_TG0_16K | TCR_TG1_16K
#else /* CONFIG_ARM64_4K_PAGES */
#define TCR_TG_FLAGS	TCR_TG0_4K | TCR_TG1_4K
#endif

#define TCR_SMP_FLAGS	TCR_SHARED

/* PTWs cacheable, inner/outer WBWA */
#define TCR_CACHE_FLAGS	TCR_IRGN_WBWA | TCR_ORGN_WBWA

#define MAIR(attr, mt)	((attr) << ((mt) * 8))

/*
 *	cpu_do_idle()
 *
 *	Idle the processor (wait for interrupt).
 */
ENTRY(cpu_do_idle)
	dsb	sy				// WFI may enter a low-power mode
	wfi
	ret
ENDPROC(cpu_do_idle)

#ifdef CONFIG_CPU_PM
/**
 * cpu_do_suspend - save CPU registers context
 *
 * x0: virtual address of context pointer
 */
ENTRY(cpu_do_suspend)
	mrs	x2, tpidr_el0
	mrs	x3, tpidrro_el0
	mrs	x4, contextidr_el1
	mrs	x5, cpacr_el1
	mrs	x6, tcr_el1
	mrs	x7, vbar_el1
	mrs	x8, mdscr_el1
	mrs	x9, oslsr_el1
	mrs	x10, sctlr_el1
	stp	x2, x3, [x0]
	stp	x4, xzr, [x0, #16]
	stp	x5, x6, [x0, #32]
	stp	x7, x8, [x0, #48]
	stp	x9, x10, [x0, #64]
	ret
ENDPROC(cpu_do_suspend)

/**
 * cpu_do_resume - restore CPU register context
 *
 * x0: Address of context pointer
 */
ENTRY(cpu_do_resume)
	ldp	x2, x3, [x0]
	ldp	x4, x5, [x0, #16]
	ldp	x6, x8, [x0, #32]
	ldp	x9, x10, [x0, #48]
	ldp	x11, x12, [x0, #64]
	msr	tpidr_el0, x2
	msr	tpidrro_el0, x3
	msr	contextidr_el1, x4
	msr	cpacr_el1, x6

	/* Don't change t0sz here, mask those bits when restoring */
	mrs	x5, tcr_el1
	bfi	x8, x5, TCR_T0SZ_OFFSET, TCR_TxSZ_WIDTH

	msr	tcr_el1, x8
	msr	vbar_el1, x9
	msr	mdscr_el1, x10
	msr	sctlr_el1, x12
	/*
	 * Restore oslsr_el1 by writing oslar_el1
	 */
	ubfx	x11, x11, #1, #1
	msr	oslar_el1, x11
	reset_pmuserenr_el0 x0			// Disable PMU access from EL0
	isb
	ret
ENDPROC(cpu_do_resume)
#endif

/*
 *	cpu_do_switch_mm(pgd_phys, tsk)
 *
 *	Set the translation table base pointer to be pgd_phys.
 *
 *	- pgd_phys - physical address of new TTB
 */
ENTRY(cpu_do_switch_mm)
	mmid	x1, x1				// get mm->context.id
	bfi	x0, x1, #48, #16		// set the ASID
	msr	ttbr0_el1, x0			// set TTBR0
	isb
alternative_if_not ARM64_WORKAROUND_CAVIUM_27456
	ret
	nop
	nop
	nop
alternative_else
	ic	iallu
	dsb	nsh
	isb
	ret
alternative_endif
ENDPROC(cpu_do_switch_mm)

	.pushsection ".idmap.text", "ax"
/*
 * void idmap_cpu_replace_ttbr1(phys_addr_t new_pgd)
 *
 * This is the low-level counterpart to cpu_replace_ttbr1, and should not be
 * called by anything else. It can only be executed from a TTBR0 mapping.
 */
ENTRY(idmap_cpu_replace_ttbr1)
	mrs	x2, daif
	msr	daifset, #0xf

	adrp	x1, empty_zero_page
	msr	ttbr1_el1, x1
	isb

	tlbi	vmalle1
	dsb	nsh
	isb

	msr	ttbr1_el1, x0
	isb

	msr	daif, x2

	ret
ENDPROC(idmap_cpu_replace_ttbr1)
	.popsection

/*
 *	__cpu_setup
 *
 *	Initialise the processor for turning the MMU on.  Return in x0 the
 *	value of the SCTLR_EL1 register.
 */
/** 20160828
 * mmu를 on 시키기 위해 필요한 설정을 한다.
 *
 * sctlr에 설정할 값을 x0에 리턴한다.
 **/
ENTRY(__cpu_setup)
	/** 20160818
	 * ARMv8 PG. Table 12-1 TLB configuration instructions
	 * TLB invalidate by VMID, All at stage 1, EL1.
	 * vttbr_el2에 저장된 VMID를 기준으로 동작한다.
	 *
	 * tlb invalidate 명령을 내리고, dsb로 명령의 완료를 대기한다.
	 **/
	tlbi	vmalle1				// Invalidate local TLB
	dsb	nsh

	/** 20160818
	 * cpacr_el1 : Architectural Feature Access Control Register
	 * FPEN, bits [21:20]
	 * Traps EL0 and EL1 accesses to the SIMD and floating-point registers
	 * to EL1, from both Execution state:
	 *  11 Does not cause any instruction to be trapped.
	 *
	 * EL1에서 Floating-point나 Adv. SIMD 레지스터를 access해도 trap을
	 * 발생시키지 않는다.
	 **/
	mov	x0, #3 << 20
	msr	cpacr_el1, x0			// Enable FP/ASIMD
	/** 20160818
	 * MDSCR_EL1, Monitor Debug System Control Register
	 * TDCC, bit [12]
	 * Traps EL0 accesses to the DCC registers to EL1, from both Execution states:
	 * 1 EL0 accesses to the DCC registers are trapped to EL1.
	 *
	 * Monitor Debug System 설정을 초기화 하고, EL0에서 EL1의 DCC 레지스터 접근을 막는다.
	 **/
	mov	x0, #1 << 12			// Reset mdscr_el1 and disable
	msr	mdscr_el1, x0			// access to the DCC from EL0
	/** 20160818
	 * EL0에서 PMU 접근을 막는다.
	 **/
	reset_pmuserenr_el0 x0			// Disable PMU access from EL0
	/*
	 * Memory region attributes for LPAE:
	 *
	 *   n = AttrIndx[2:0]
	 *			n	MAIR
	 *   DEVICE_nGnRnE	000	00000000
	 *   DEVICE_nGnRE	001	00000100
	 *   DEVICE_GRE		010	00001100
	 *   NORMAL_NC		011	01000100
	 *   NORMAL		100	11111111
	 *   NORMAL_WT		101	10111011
	 */
	ldr	x5, =MAIR(0x00, MT_DEVICE_nGnRnE) | \
		     MAIR(0x04, MT_DEVICE_nGnRE) | \
		     MAIR(0x0c, MT_DEVICE_GRE) | \
		     MAIR(0x44, MT_NORMAL_NC) | \
		     MAIR(0xff, MT_NORMAL) | \
		     MAIR(0xbb, MT_NORMAL_WT)
	msr	mair_el1, x5
	/*
	 * Prepare SCTLR
	 */
	/** 20160828
	 * sctlr_el1를 읽어 crval의 clear와 set 값을 적용해 값을 준비한다.
	 **/
	adr	x5, crval
	ldp	w5, w6, [x5]
	mrs	x0, sctlr_el1
	bic	x0, x0, x5			// clear bits
	orr	x0, x0, x6			// set bits
	/*
	 * Set/prepare TCR and TTBR. We use 512GB (39-bit) address range for
	 * both user and kernel.
	 */
	ldr	x10, =TCR_TxSZ(VA_BITS) | TCR_CACHE_FLAGS | TCR_SMP_FLAGS | \
			TCR_TG_FLAGS | TCR_ASID16 | TCR_TBI0
	tcr_set_idmap_t0sz	x10, x9

	/*
	 * Read the PARange bits from ID_AA64MMFR0_EL1 and set the IPS bits in
	 * TCR_EL1.
	 */
	/** 20160828
	 * ID_AA64MMFR0_EL1로부터 PARange를 읽어 TCR_EL1의 IPS 비트를 설정.
	 * (Intermediate Physical Address Size)
	 **/
	mrs	x9, ID_AA64MMFR0_EL1
	/** 20160828
	 * x10의 lsb 32부터 3비트는 x9의 0비트부터 3비트로 대체된다.
	 * ID_AA64MMFR0_EL1 [3:0]은 PARange.
	 **/
	bfi	x10, x9, #32, #3
#ifdef CONFIG_ARM64_HW_AFDBM
	/*
	 * Hardware update of the Access and Dirty bits.
	 */
	/** 20160828
	 * MMFR1을 읽어 지원 여부에 따라 access flag와 dirty flag를 설정.
	 **/
	mrs	x9, ID_AA64MMFR1_EL1
	and	x9, x9, #0xf
	cbz	x9, 2f
	cmp	x9, #2
	b.lt	1f
	orr	x10, x10, #TCR_HD		// hardware Dirty flag update
1:	orr	x10, x10, #TCR_HA		// hardware Access flag update
2:
#endif	/* CONFIG_ARM64_HW_AFDBM */
	msr	tcr_el1, x10
	ret					// return to head.S
ENDPROC(__cpu_setup)

	/*
	 * We set the desired value explicitly, including those of the
	 * reserved bits. The values of bits EE & E0E were set early in
	 * el2_setup, which are left untouched below.
	 *
	 *                 n n            T
	 *       U E      WT T UD     US IHBS
	 *       CE0      XWHW CZ     ME TEEA S
	 * .... .IEE .... NEAI TE.I ..AD DEN0 ACAM
	 * 0011 0... 1101 ..0. ..0. 10.. .0.. .... < hardware reserved
	 * .... .1.. .... 01.1 11.1 ..01 0.01 1101 < software settings
	 */
	.type	crval, #object
	/** 20160828
	 * sctlr 설정 비트. EE와 E0E는 el2_setup에서 설정되므로 reset 안함.
	 **/
crval:
	.word	0xfcffffff			// clear
	.word	0x34d5d91d			// set
