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
#include <asm/pgtable-hwdef.h>
#include <asm/pgtable.h>
#include <asm/cpufeature.h>
#include <asm/alternative.h>

#include "proc-macros.S"

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

/** 20161115
 * MAIR은 8개의 attribute map이다.
 * page table entry에는 이 map의 index[2:0]가 적혀 있다.
 **/
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
	mrs	x5, mair_el1
	mrs	x6, cpacr_el1
	mrs	x7, ttbr1_el1
	mrs	x8, tcr_el1
	mrs	x9, vbar_el1
	mrs	x10, mdscr_el1
	mrs	x11, oslsr_el1
	mrs	x12, sctlr_el1
	stp	x2, x3, [x0]
	stp	x4, x5, [x0, #16]
	stp	x6, x7, [x0, #32]
	stp	x8, x9, [x0, #48]
	stp	x10, x11, [x0, #64]
	str	x12, [x0, #80]
	ret
ENDPROC(cpu_do_suspend)

/**
 * cpu_do_resume - restore CPU register context
 *
 * x0: Physical address of context pointer
 * x1: ttbr0_el1 to be restored
 *
 * Returns:
 *	sctlr_el1 value in x0
 */
ENTRY(cpu_do_resume)
	/*
	 * Invalidate local tlb entries before turning on MMU
	 */
	tlbi	vmalle1
	ldp	x2, x3, [x0]
	ldp	x4, x5, [x0, #16]
	ldp	x6, x7, [x0, #32]
	ldp	x8, x9, [x0, #48]
	ldp	x10, x11, [x0, #64]
	ldr	x12, [x0, #80]
	msr	tpidr_el0, x2
	msr	tpidrro_el0, x3
	msr	contextidr_el1, x4
	msr	mair_el1, x5
	msr	cpacr_el1, x6
	msr	ttbr0_el1, x1
	msr	ttbr1_el1, x7
	tcr_set_idmap_t0sz x8, x7
	msr	tcr_el1, x8
	msr	vbar_el1, x9
	msr	mdscr_el1, x10
	/*
	 * Restore oslsr_el1 by writing oslar_el1
	 */
	ubfx	x11, x11, #1, #1
	msr	oslar_el1, x11
	reset_pmuserenr_el0 x0			// Disable PMU access from EL0
	mov	x0, x12
	dsb	nsh		// Make sure local tlb invalidation completed
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
/** 20161126
 * pgd 물리주소의 상위 16비트를 mm->context.id (ASID)로 덮어쓴다.
 *
 * bfi: bitfield insert
 *   x1의 lsb부터 width(16)만큼 추출해 x0의 48비트부터 덮어쓴다.
 **/
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
/** 20161126
 * ttbr1_el1을 new_pgd로 채운다.
 **/
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
ENTRY(__cpu_setup)
	/** 20161115
	 * TLB Invalidate by VMID, All at stage 1, EL1
	 * Invalidate all EL1&0 regime stage 1 TLB entries for the current VMID.
	 * EL1에서 사용한 local TLB를 무효화. non-shareable로 현재 코어에만 적용
	 **/
	tlbi	vmalle1				// Invalidate local TLB
	dsb	nsh

	/** 20161122
	 * CPACR_EL1, Architectural Feature Access Control Register
	 * FPEN 비트를 설정해 FP/SIMD 명령이 EL1으로 트랩되지 않고 허용되도록 설정.
	 **/
	mov	x0, #3 << 20
	msr	cpacr_el1, x0			// Enable FP/ASIMD
	mov	x0, #1 << 12			// Reset mdscr_el1 and disable
	/** 20161122
	 * MDSCR_EL1, Monitor Debug System Control Register
	 *    Traps EL0 accesses to the DCC registers to EL1, from both Execution states:
	 *    EL1로 트랩되도록 설정하는 것은 disable.

	 *    TDCC 비트를 설정해 EL0에서 DBG 레지스터 접근하면 EL1으로 trap 시킨다.
	 *
	 * reset_pmuserenr_el0 매크로로 EL0에서 PMU 접근을 막는다.
	 **/
	msr	mdscr_el1, x0			// access to the DCC from EL0
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
	/** 20161115
	 * MAIR_EL1 : Memory Attribute Indirection Register (EL1)
	 * MAIR의 8개의 attribute를 원하는 타입으로 설정한다.
	 *
	 * table descriptor 중 Table entry와 Block entry의 Lower attributes 중
	 * Indx[4:2]는 MAIR_ELn 레지스터의 attribute index를 의미한다.
	 *
	 *   DEVICE_nGnRnE	000	00000000	Device non-Gathering, non-Reordering, No Early write acknowledgement.
	 *						Equivalent to the Strongly-ordered memory type in earlier versions of the architecture.
	 *						=> pgprot_noncached에서 사용
	 *   DEVICE_nGnRE	001	00000100	Device non-Gathering, non-Reordering, Early Write Acknowledgement.
	 *						Equivalent to the Device memory type in earlier versions of the architecture.
	 *						=> pgprot_device, ioremap에서 사용
	 *   DEVICE_GRE		010	00001100	Device Gathering, Reordering, Early Write Acknowledgement.
	 *						Device-GRE memory has the fewest constraints. It behaves similar to Normal memory,
	 *						with the restriction that speculative accesses to Device-GRE memory is forbidden.
	 *   NORMAL_NC		011	01000100	Normal Memory, Outer Non-cacheable / Normal memory, Inner Non-cacheable
							=> pgprot_writecombine, dma contiguous에서 사용
	 *   NORMAL		100	11111111	Normal Memory, Outer Write-back non-transient + Outer Read Alloc + Outer Write Alloc
	 *						Normal Memory, Inner Write-back non-transient + Inner Read Alloc + Innter Write Alloc
	 *   NORMAL_WT		101	10111011	Normal Memory, Outer Write-through non-transient + Outer Read Alloc + Outer Write Alloc
	 *						Normal Memory, Inner Write-through non-transient + Inner Read Alloc + Innter Write Alloc
	 *   ARMv8 PG 13.1 Memory type 참고.
	 *   Gathering, Re-ordering, Early Write Acknowledgement.
	 **/
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
	/** 20161115
	 * sctlr_el1의 값을 읽어와 미리 준비된 clear, set를 적용해 값을 만든다.
	 *
	 * 이 값은 __enable_mmu로 리턴 후 sctlr_el0에 쓰인다.
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
	/** 20161115
	 * TCR 설정값을 만든다.
	 * TCR_TxSZ는 kernel/user에서 사용할 VA_BITS의 크기
	 * TCR_CACHE_FLAGS는 TTBR1/TTBR0을 사용한 변환 테이블 순회시 접근하는
	 *   메모리에 대한 Inner/Outer Cacheability 속성을 정의한다.
	 * TCR_SMP_FLAGS는 TTBR1/TTBR0의 변환 테이블 순회시 접근하는
	 *   shareability 속성을 Inner shareable로 사용한다.
	 * TCR_TG_FLAGS는 TTBR1/TTBR0의 Granule size를 4K로 설정한다.
	 * TCR_ASID16는 ASID Size를 16비트로 선택한다. TTBR0_EL1, TTBR1_EL1의 상위 16비트가 TLB 내의 할당 및 매칭에 사용된다.
	 * TCR_TBI0는 TTBR0_EL1에 대한 address matching에서 TBI를 사용할지 말지 결정한다. Top Byte Ignore.
	 *   이 값은 1로 설정되어 user address space에서 무시된다.
	 *
	 * idmap을 위해 계산해둔 t0sz를 덮어 쓴다.
	 **/
	ldr	x10, =TCR_TxSZ(VA_BITS) | TCR_CACHE_FLAGS | TCR_SMP_FLAGS | \
			TCR_TG_FLAGS | TCR_ASID16 | TCR_TBI0
	tcr_set_idmap_t0sz	x10, x9

	/*
	 * Read the PARange bits from ID_AA64MMFR0_EL1 and set the IPS bits in
	 * TCR_EL1.
	 */
	/** 20161115
	 * ID_AA64MMFR0_EL1의 PARange로 TCR_EL1 레지스터의 IPS bits [34:32]를
	 * 덮어쓴다.
	 *   IPS : Intermediate Physical Address Size
	 **/
	mrs	x9, ID_AA64MMFR0_EL1
	bfi	x10, x9, #32, #3
#ifdef CONFIG_ARM64_HW_AFDBM
	/*
	 * Hardware update of the Access and Dirty bits.
	 */
	/** 20161115
	 * Datasheet ARMv8.1 supplement에 명시.
	 * ID_AA64MMFR1_EL1 레지스터는
	 * v8.1 이전은 reserved 값,
	 * v8.1은 Access flag와 dirty state가 hardware에 의한 업데이트 가능여부
	 *
	 * TCR_EL1 역시 ARMv8.1부터 추가 비트 나열
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
	/** 20161115
	 * 최종적으로 설정된 tcr_el1을 레지스터에 기록하고, ret.
	 * 호출 전 lr로 설정한 __enable_mmu로 복귀
	 **/
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
	/** 20161115
	 * sctlr 레지스터에서 clear 할 비트와 설정할 비트가 미리 준비되어 있다.
	 * EE와 E0E 비트는 el2_setup에서 설정했기 때문에 보존한다.
	 *
	 * M(비트 0) 값은 MMU enable이다.
	 * I(비트 12)값은 Instruction cache
	 * D(비트 2) 값은 Data cache
	 **/
	.type	crval, #object
crval:
	.word	0xfcffffff			// clear
	.word	0x34d5d91d			// set
