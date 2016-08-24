
#ifndef __ASM_BOOT_H
#define __ASM_BOOT_H

#include <asm/sizes.h>

/*
 * arm64 requires the DTB to be 8 byte aligned and
 * not exceed 2MB in size.
 */
#define MIN_FDT_ALIGN		8
#define MAX_FDT_SIZE		SZ_2M

/*
 * arm64 requires the kernel image to placed
 * TEXT_OFFSET bytes beyond a 2 MB aligned base
 */
/** 20160824
 * arm64는 kernel image가 TEXT_OFFSET 바이트 위의 2MB 정렬된 베이스에
 * 위치하도록 요구한다. 왜???
 **/
#define MIN_KIMG_ALIGN		SZ_2M

#endif
