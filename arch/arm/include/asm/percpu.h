/*
 * Copyright 2012 Calxeda, Inc.
 *
 * This program is free software; you can redistribute it and/or modify it
 * under the terms and conditions of the GNU General Public License,
 * version 2, as published by the Free Software Foundation.
 *
 * This program is distributed in the hope it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
 * FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
 * more details.
 *
 * You should have received a copy of the GNU General Public License along with
 * this program.  If not, see <http://www.gnu.org/licenses/>.
 */
#ifndef _ASM_ARM_PERCPU_H_
#define _ASM_ARM_PERCPU_H_

/*
 * Same as asm-generic/percpu.h, except that we store the per cpu offset
 * in the TPIDRPRW. TPIDRPRW only exists on V6K and V7
 */
#if defined(CONFIG_SMP) && !defined(CONFIG_CPU_V6)
/** 20160612
 * ARM에서 만들어 놓은 용도로 사용하지 않고,
 * percpu에서의 offset을 저장하는 용도로 사용한다.
 *
 * 접근 속도 향상을 목적으로.
 **/
static inline void set_my_cpu_offset(unsigned long off)
{
	/* Set TPIDRPRW */
	asm volatile("mcr p15, 0, %0, c13, c0, 4" : : "r" (off) : "memory");
}

/** 20160612
 * cpu의 offset을 가져올 때도 register에 저장된 offset 값을 읽어온다.
 **/
static inline unsigned long __my_cpu_offset(void)
{
	unsigned long off;

	/*
	 * Read TPIDRPRW.
	 * We want to allow caching the value, so avoid using volatile and
	 * instead use a fake stack read to hazard against barrier().
	 */
	asm("mrc p15, 0, %0, c13, c0, 4" : "=r" (off)
		: "Q" (*(const unsigned long *)current_stack_pointer));

	return off;
}
#define __my_cpu_offset __my_cpu_offset()
#else
#define set_my_cpu_offset(x)	do {} while(0)

#endif /* CONFIG_SMP */

#include <asm-generic/percpu.h>

#endif /* _ASM_ARM_PERCPU_H_ */
