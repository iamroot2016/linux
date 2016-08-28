/*
 * Kernel page table mapping
 *
 * Copyright (C) 2015 ARM Ltd.
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

#ifndef __ASM_KERNEL_PGTABLE_H
#define __ASM_KERNEL_PGTABLE_H

#include <asm/sparsemem.h>

/*
 * The linear mapping and the start of memory are both 2M aligned (per
 * the arm64 booting.txt requirements). Hence we can use section mapping
 * with 4K (section size = 2M) but not with 16K (section size = 32M) or
 * 64K (section size = 512M).
 */
/** 20160827
 * arm64 booting.txt 요구사항에 따라 linear mapping과 memory의 시작 위치는
 * 2MB 정렬되어야 한다.
 * 따라서 page가 4K일 때는 section mapping을 사용하고 (4K * 512 = 2M)
 * 16K나 64K일 경우는 그렇지 않는다(page mapping).
 **/
#ifdef CONFIG_ARM64_4K_PAGES
#define ARM64_SWAPPER_USES_SECTION_MAPS 1
#else
#define ARM64_SWAPPER_USES_SECTION_MAPS 0
#endif

/*
 * The idmap and swapper page tables need some space reserved in the kernel
 * image. Both require pgd, pud (4 levels only) and pmd tables to (section)
 * map the kernel. With the 64K page configuration, swapper and idmap need to
 * map to pte level. The swapper also maps the FDT (see __create_page_tables
 * for more information). Note that the number of ID map translation levels
 * could be increased on the fly if system RAM is out of reach for the default
 * VA range, so pages required to map highest possible PA are reserved in all
 * cases.
 */
/** 20160827
 * idmap과 swapper 페이지 테이블들은 커널이미지에서 예약된 공간이 필요하다.
 * 둘 모두 커널을 매핑하기 위해 pgd, pud (4 level인 경우), pmd 테이블들이 필요하다.
 * 64K 페이지 설정에서, swapper와 idmap은 pte 레벨을 매핑해야 한다.
 * swapper는 또한 FDT도 매핑해야 한다.
 *
 * SWAPPER가 section mapping을 사용하는 경우
 *   swapper pgtable level은 pgtable level보다 1 작은 값.
 *   idmap pgtable level은 physical address를 표현하기 위한 hw pgtable level보다 1 작은 값. 왜???
 * 그렇지 않은 경우 (page mapping을 사용하는 경우)
 *   swapper pgtable level은 pgtable level (page) 값.
 *   idmap pgtable level은 physical address를 표현하기 위한 hw pgtable level보다 1 작은 값. 왜???
 **/
#if ARM64_SWAPPER_USES_SECTION_MAPS
#define SWAPPER_PGTABLE_LEVELS	(CONFIG_PGTABLE_LEVELS - 1)
#define IDMAP_PGTABLE_LEVELS	(ARM64_HW_PGTABLE_LEVELS(PHYS_MASK_SHIFT) - 1)
#else
#define SWAPPER_PGTABLE_LEVELS	(CONFIG_PGTABLE_LEVELS)
#define IDMAP_PGTABLE_LEVELS	(ARM64_HW_PGTABLE_LEVELS(PHYS_MASK_SHIFT))
#endif

/** 20160827
 * 각각의 레벨마다 페이지 테이블을 구성하기 위해 하나의 페이지를 사용한다.
 **/
#define SWAPPER_DIR_SIZE	(SWAPPER_PGTABLE_LEVELS * PAGE_SIZE)
#define IDMAP_DIR_SIZE		(IDMAP_PGTABLE_LEVELS * PAGE_SIZE)

/* Initial memory map size */
/** 20160828
 * SWAPPER가 섹션 매핑을 하는 경우 BLOCK은 section.
 * 그 외( 페이지 매핑을 하는 경우) BLOCK은 page.
 **/
#if ARM64_SWAPPER_USES_SECTION_MAPS
#define SWAPPER_BLOCK_SHIFT	SECTION_SHIFT
#define SWAPPER_BLOCK_SIZE	SECTION_SIZE
#define SWAPPER_TABLE_SHIFT	PUD_SHIFT
#else
#define SWAPPER_BLOCK_SHIFT	PAGE_SHIFT
#define SWAPPER_BLOCK_SIZE	PAGE_SIZE
#define SWAPPER_TABLE_SHIFT	PMD_SHIFT
#endif

/* The size of the initial kernel direct mapping */
#define SWAPPER_INIT_MAP_SIZE	(_AC(1, UL) << SWAPPER_TABLE_SHIFT)

/*
 * Initial memory map attributes.
 */
/** 20160828
 * swapper page table PTE/PMD flag 속성
 **/
#define SWAPPER_PTE_FLAGS	(PTE_TYPE_PAGE | PTE_AF | PTE_SHARED)
#define SWAPPER_PMD_FLAGS	(PMD_TYPE_SECT | PMD_SECT_AF | PMD_SECT_S)

/** 20160828
 * section mapping을 사용할 경우 PMD에 해당하는 속성을,
 * page mapping을 사용할 경우 PTE에 해당하는 속성을 정의
 **/
#if ARM64_SWAPPER_USES_SECTION_MAPS
#define SWAPPER_MM_MMUFLAGS	(PMD_ATTRINDX(MT_NORMAL) | SWAPPER_PMD_FLAGS)
#else
#define SWAPPER_MM_MMUFLAGS	(PTE_ATTRINDX(MT_NORMAL) | SWAPPER_PTE_FLAGS)
#endif

/*
 * To make optimal use of block mappings when laying out the linear
 * mapping, round down the base of physical memory to a size that can
 * be mapped efficiently, i.e., either PUD_SIZE (4k granule) or PMD_SIZE
 * (64k granule), or a multiple that can be mapped using contiguous bits
 * in the page tables: 32 * PMD_SIZE (16k granule)
 */
#if defined(CONFIG_ARM64_4K_PAGES)
#define ARM64_MEMSTART_SHIFT		PUD_SHIFT
#elif defined(CONFIG_ARM64_16K_PAGES)
#define ARM64_MEMSTART_SHIFT		(PMD_SHIFT + 5)
#else
#define ARM64_MEMSTART_SHIFT		PMD_SHIFT
#endif

/*
 * sparsemem vmemmap imposes an additional requirement on the alignment of
 * memstart_addr, due to the fact that the base of the vmemmap region
 * has a direct correspondence, and needs to appear sufficiently aligned
 * in the virtual address space.
 */
#if defined(CONFIG_SPARSEMEM_VMEMMAP) && ARM64_MEMSTART_SHIFT < SECTION_SIZE_BITS
#define ARM64_MEMSTART_ALIGN	(1UL << SECTION_SIZE_BITS)
#else
#define ARM64_MEMSTART_ALIGN	(1UL << ARM64_MEMSTART_SHIFT)
#endif

#endif	/* __ASM_KERNEL_PGTABLE_H */
