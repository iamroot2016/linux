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


/*
 * The linear mapping and the start of memory are both 2M aligned (per
 * the arm64 booting.txt requirements). Hence we can use section mapping
 * with 4K (section size = 2M) but not with 16K (section size = 32M) or
 * 64K (section size = 512M).
 */
/** 20161113
 * linear mapping과 메모리의 시작은 2MB 정렬되어야 한다(arm64 booting.txt 요구사항).
 * 따라서 4KB page table을 사용하는 경우에는 section mapping을 할 수 있고, 16KB와 64KB는 섹션 매핑을 할 수 없다.
 *
 * 따라서 4KB 페이지를 사용하면 swapper 페이지 테이블에서 섹션단위 매핑을 사용한다.
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
/** 20161113
 * idmap과 swapper 페이지 테이블은 커널 이미지에서 예약된 공간이 필요하다.
 * pgd, pud(4level인 경우), pmd 테이블은 커널에 (section) 매핑된다.
 *
 * 섹션 매핑을 사용하므로 PGTABLE LEVEL에서 하나씩 빼준다.
 * (va 39bit, 4KB page인 경우 pgtable level은 3이다)
 *   SWAPPER_PGTABLE_LEVELS     3-1=2
 *   IDMAP_PGTABLE_LEVELS	4-1=3
 **/
#if ARM64_SWAPPER_USES_SECTION_MAPS
#define SWAPPER_PGTABLE_LEVELS	(CONFIG_PGTABLE_LEVELS - 1)
#define IDMAP_PGTABLE_LEVELS	(ARM64_HW_PGTABLE_LEVELS(PHYS_MASK_SHIFT) - 1)
#else
#define SWAPPER_PGTABLE_LEVELS	(CONFIG_PGTABLE_LEVELS)
#define IDMAP_PGTABLE_LEVELS	(ARM64_HW_PGTABLE_LEVELS(PHYS_MASK_SHIFT))
#endif

#define SWAPPER_DIR_SIZE	(SWAPPER_PGTABLE_LEVELS * PAGE_SIZE)
#define IDMAP_DIR_SIZE		(IDMAP_PGTABLE_LEVELS * PAGE_SIZE)

/* Initial memory map size */
/** 20161113
 * SECTION MAPPING 을 사용하는 경우 BLOCK 단위는 SECTION.
 *   SECTION_SHIFT는 PMD_SHIFT
 * 그렇지 않을 경우 PAGE 단위.
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
#define SWAPPER_PTE_FLAGS	(PTE_TYPE_PAGE | PTE_AF | PTE_SHARED)
#define SWAPPER_PMD_FLAGS	(PMD_TYPE_SECT | PMD_SECT_AF | PMD_SECT_S)

/** 20161113
 * section mapping 여부에 따라 MMU flag가 달라진다.
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
#ifdef CONFIG_ARM64_64K_PAGES
#define ARM64_MEMSTART_ALIGN	SZ_512M
#else
#define ARM64_MEMSTART_ALIGN	SZ_1G
#endif

#endif	/* __ASM_KERNEL_PGTABLE_H */
