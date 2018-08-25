/*
 *  linux/arch/arm/boot/compressed/head.S
 *
 *  Copyright (C) 1996-2002 Russell King
 *  Copyright (C) 2004 Hyok S. Choi (MPU support)
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License version 2 as
 * published by the Free Software Foundation.
 */
#include <linux/linkage.h>
#include <asm/assembler.h>
#include <asm/v7m.h>

#include "efi-header.S"

 AR_CLASS(	.arch	armv7-a	)
 M_CLASS(	.arch	armv7-m	)

/*
 * Debugging stuff
 *
 * Note that these macros must not contain any code which is not
 * 100% relocatable.  Any attempt to do so will result in a crash.
 * Please select one of the following when turning on debugging.
 */
#ifdef DEBUG

#if defined(CONFIG_DEBUG_ICEDCC)

#if defined(CONFIG_CPU_V6) || defined(CONFIG_CPU_V6K) || defined(CONFIG_CPU_V7)
		.macro	loadsp, rb, tmp
		.endm
		.macro	writeb, ch, rb
		mcr	p14, 0, \ch, c0, c5, 0
		.endm
#elif defined(CONFIG_CPU_XSCALE)
		.macro	loadsp, rb, tmp
		.endm
		.macro	writeb, ch, rb
		mcr	p14, 0, \ch, c8, c0, 0
		.endm
#else
		.macro	loadsp, rb, tmp
		.endm
		.macro	writeb, ch, rb
		mcr	p14, 0, \ch, c1, c0, 0
		.endm
#endif

#else

#include CONFIG_DEBUG_LL_INCLUDE

		.macro	writeb,	ch, rb
		senduart \ch, \rb
		.endm

#if defined(CONFIG_ARCH_SA1100)
		.macro	loadsp, rb, tmp
		mov	\rb, #0x80000000	@ physical base address
#ifdef CONFIG_DEBUG_LL_SER3
		add	\rb, \rb, #0x00050000	@ Ser3
#else
		add	\rb, \rb, #0x00010000	@ Ser1
#endif
		.endm
#else
		.macro	loadsp,	rb, tmp
		addruart \rb, \tmp
		.endm
#endif
#endif
#endif

		.macro	kputc,val
		mov	r0, \val
		bl	putc
		.endm

		.macro	kphex,val,len
		mov	r0, \val
		mov	r1, #\len
		bl	phex
		.endm

		.macro	debug_reloc_start
#ifdef DEBUG
		kputc	#'\n'
		kphex	r6, 8		/* processor id */
		kputc	#':'
		kphex	r7, 8		/* architecture id */
#ifdef CONFIG_CPU_CP15
		kputc	#':'
		mrc	p15, 0, r0, c1, c0
		kphex	r0, 8		/* control reg */
#endif
		kputc	#'\n'
		kphex	r5, 8		/* decompressed kernel start */
		kputc	#'-'
		kphex	r9, 8		/* decompressed kernel end  */
		kputc	#'>'
		kphex	r4, 8		/* kernel execution address */
		kputc	#'\n'
#endif
		.endm

		.macro	debug_reloc_end
#ifdef DEBUG
		kphex	r5, 8		/* end of kernel */
		kputc	#'\n'
		mov	r0, r4
		bl	memdump		/* dump 256 bytes at start of kernel */
#endif
		.endm

		.section ".start", #alloc, #execinstr
/*
 * sort out different calling conventions
 */
		.align
		/*
		 * Always enter in ARM state for CPUs that support the ARM ISA.
		 * As of today (2014) that's exactly the members of the A and R
		 * classes.
		 */
 AR_CLASS(	.arm	)			@ 180623 hs.kim CONFIG_CPU_V7M 가 define 되어 있지 않을 경우만, 의미 있음. 
 								@ 180623 hs.kim AR_CLASS(xxx) xxx 로 동작.. 즉, .arm 과 동일한 의미.

start:		@ 180609 bj.jung 117 번 라인에서 호출, 추가 확인필요 
		.type	start,#function		@ 180623 hs.kim .type에 의해 'start'라는 함수(fucntion)를 심볼로 정의.
		.rept	7
		__nop
		.endr
#ifndef CONFIG_THUMB2_KERNEL
		mov	r0, r0				@ 180609 bj.jung __nop와 동일 명령어,
								@ 180609 bj.jung http://www.iamroot.org/xe/index.php?mid=Programming&document_srl=13334   
#else
 AR_CLASS(	sub	pc, pc, #3	)	@ A/R: switch to Thumb2 mode
  M_CLASS(	nop.w			)	@ M: already in Thumb2 mode
		.thumb
#endif
		W(b)	1f				@ 180609 bj.jung b.w는 b가 4byte 명령어 셋으로 인식하게 함, 0x0000_0001
								@ 180609 bj.jung arch/arm/include/asm/unified.h

		.word	_magic_sig	@ Magic numbers to help the loader
		.word	_magic_start	@ absolute load/run zImage address
		.word	_magic_end	@ zImage end address
		.word	0x04030201	@ endianness flag

		__EFI_HEADER
1:
 ARM_BE8(	setend	be		)	@ go BE8 if compiled for BE8
								@ 180609 bj.jung CPSR 레지스터 9번 비트 endian 설정, little endian 사용(?)으로 실행 안됨.
							    @ 180609 bj.jung http://forum.falinux.com/zbxe/index.php?document_srl=575677&mid=lecture_tip								 
 AR_CLASS(	mrs	r9, cpsr	)		@ 180623 hs.kim cpsr의 내용을 r9 레지스터로 저장.
#ifdef CONFIG_ARM_VIRT_EXT
		bl	__hyp_stub_install	@ get into SVC mode, reversibly
								@ 180609 bj.jung 수행되는 내용 없음.
#endif
		mov	r7, r1			@ save architecture ID
		mov	r8, r2			@ save atags pointer
							@ 180609 bj.jung bootloader에서 받은 값 저장 
							 
#ifndef CONFIG_CPU_V7M
		/*
		 * Booting from Angel - need to enter SVC mode and disable
		 * FIQs/IRQs (numeric definitions from angel arm.h source).
		 * We only do this if we were in user mode on entry.
		 */
		mrs	r2, cpsr		@ get current mode
		tst	r2, #3			@ not user?
						
							@ 180609 bj.jung  
							@ tst, CPSR := r2 and #3(0b11)
							@ usermode 일 경우 다른 모드로 변환 안됨
							@ 10000 : usermode
							@ 10001 : fiq
							@ 10010 : irq
							@ 10011 : svc
							@ 10111 : abt
							@ 11011 : und
							@ 11111 : sys
		bne	not_angel		
							@ 180609 bj.jung
							@ tst 연산 결과로 CPSR의 Z플래그가 변경 될 수 있으며(user 모드 일 경우에만,  Z 플래그 1)
							@ CPSR 의 모드를 검사해서 user 모드가 아닐경우 분기 함.
							@ zero condtion flag를 확인
							@ Z == 1 : eq 
							@ Z == 0 : neq 
 							@ https://blogs.msdn.microsoft.com/ntdebugging/2013/11/22/understanding-arm-assembly-part-1/
							
		mov	r0, #0x17		@ angel_SWIreason_EnterSVC
 ARM(		swi	0x123456	)	@ angel_SWI_ARM
 THUMB(		svc	0xab		)	@ angel_SWI_THUMB
not_angel:						@ 180623 hs.kim 현재 cpsr에서 우리가 알고 있는 값은, mode 정보(SVC mode), z 정보(0:0이 아닌 값) 그리고 endian 정보(0:little).
		safe_svcmode_maskall r0		@ 180623 hs.kim 현재 cpsr의 모드를 SVC모드로 바꾸고, Interrup와 Fast-Interrup를 비활성화 하는 코드.. 
		msr	spsr_cxsf, r9		@ Save the CPU boot mode in
								@ 180623 hs.kim... safe_svcmode_maskall에서 cspr을 SVC모드로 바꾸기 이전의 상태(r9에 백업했던 cpsr)를 spsr_cxsf에 저장(백업)
								@					나중에 기존의 모드(?)로 돌아가야 할 경우, spsr_cxsf의 값을 cpsr로 가져오면 될 듯.. 
								@					spsr_cxsf에서 c, x, s, f는 하위부터 각각 8bit를 의미한다. 즉, spsr의 모든 비트에 해당함.
								
						@ SPSR
#endif
		/*
		 * Note that some cache flushing and other stuff may
		 * be needed here - is there an Angel SWI call for this?
		 */

		/*
		 * some architecture specific code can be inserted
		 * by the linker here, but it should preserve r7, r8, and r9.
		 */

		.text

		@ 180623 k15b_last
		@ 180623 hs.kim 					================================================]
		@ 참고 웹페이지.. 
		@ https://casionwoo.github.io/jekyll/update/2016/08/03/start-symbol-cont2.html
		@ http://jake.dothome.co.kr/head-s-1/
		@ CONFIG_AUTO_ZRELADDR 옵션이 사용될 경우, decompressed 커널이 시작할 물리 주소를 자동으로 계산한다. 
		@ 추가로 자세한 내용은 차후에..... -_-;;;
#ifdef CONFIG_AUTO_ZRELADDR					
@ 180623 hs.kim... 라즈베리파이의 .config 파일에 Y로 설정되어 있음. 사용됨.
		/*
		 * Find the start of physical memory.  As we are executing
		 * without the MMU on, we are in the physical address space.
		 * We just need to get rid of any offset by aligning the
		 * address.
		 *
		 * This alignment is a balance between the requirements of
		 * different platforms - we have chosen 128MB to allow
		 * platforms which align the start of their physical memory
		 * to 128MB to use this feature, while allowing the zImage
		 * to be placed within the first 128MB of memory on other
		 * platforms.  Increasing the alignment means we place
		 * stricter alignment requirements on the start of physical
		 * memory, but relaxing it means that we break people who
		 * are already placing their zImage in (eg) the top 64MB
		 * of this range.
		 */
		mov	r4, pc                     @ 180630 dh.park pc는 0으로 가정
		and	r4, r4, #0xf8000000
		/* Determine final kernel image address. */
		add	r4, r4, #TEXT_OFFSET       @ 180630 dh.park /arch/arm/Makefile 에 TEXT_OFFSET := $(textofs-y) 으로 정의되어 있음. textofs-y는 textofs-y :=0x00008000 

#else
		ldr	r4, =zreladdr
#endif
		@ 180623 hs.kim 					[================================================

		
		@ 180630_start dh.park
		/*
		 * Set up a page table only if it won't overwrite ourself.
		 * That means r4 < pc || r4 - 16k page directory > &_end.
		 * Given that r4 > &_end is most unfrequent, we add a rough
		 * additional 1MB of room for a possible appended DTB.
		 */
		mov	r0, pc              @ 180630 dh.park r0는 모름. r4보다 클수도 작을 수도 있다.
		cmp	r0, r4				@ 180630 dh.park r0 < r4 인 경우에 cpsr의 c 비트가 0로 셋팅. 
		ldrcc	r0, LC0+32		@ 180630 dh.park XXX{cc}는 이전 연산(지금 소스에서는 cmp)의 결과값이 저장되는 cpsr의 C 비트가 0인 경우에 동작한다. 
                                @ 180630 r0에 LC0+32주소 값인  _end - restart + 16384 + 1024*1024 을 복사한다. 
		addcc	r0, r0, pc		@ r0 += pc
		cmpcc	r4, r0			@ 커널이 복사될 주소(r4)와 r0값을 비교. r4 < r0 이면 c가 0이 되고 orrcc가 실행됨.
		orrcc	r4, r4, #1		@ remember we skipped cache_on 
								@ r4 = r4 | 1 
		blcs	cache_on		@ cpsr의 c 비트가 1이면 실행한다. 
		@ 20180828_start

restart:	adr	r0, LC0
		@ 20180728 je.park LC0 정의:./arch/arm/boot/compressed/head.S +635
		@ LC0 의 주소를 가져옴
		ldmia	r0, {r1, r2, r3, r6, r10, r11, r12}
		@ 20180728 je.park LDM : 다중-레지스터 전송 명령어 중 하나로 여러 개의 레지스터르 읽어 들임
		@ LDMIA : r0에 있는 주소 값 기준으로 4byte(.word)씩 데이터를 읽어와서 각각 r1, r2, r3, r6, r10, r11, r12에 입력합
		ldr	sp, [r0, #28]
		@ 20180728 je.park LDR (immediate offset), r0에서 28 offset의 값을 sp에 로드 함
		@.word	.L_user_stack_end	@ sp, head.S(같은 파일) 맨 아래에 정의되어 있음
		@ Example : LDR     r8,[r10]        ; loads R8 from the address in R10.

		/*
		 * We might be running at a different address.  We need
		 * to fix up various pointers.
		 */
		sub	r0, r0, r1		@ calculate the delta offset
		@ 20180728 je.park 11.140 SUB, r0에서 r1을 뺀 값을 r0에 저장
		add	r6, r6, r0		@ _edata
		@ 20180728 je.park r6에 r0를 더한 값을 r6에 저장
		add	r10, r10, r0		@ inflated kernel size location
		@ 20180728 je.park r10에 r0를 더한 값을 r10에 저장
		@ 20180728 je.park k15b_question r0 값은 변함이 없을 것 같은데 LC0 레이블의 주소값 과 구조체 내부 첫번째(.word LC0)의 값이 실제 실행 될 때 서로 다른가?

		/*
		 * The kernel build system appends the size of the
		 * decompressed kernel at the end of the compressed data
		 * in little-endian form.
		 */
		ldrb	r9, [r10, #0]
		@ 20180728 je.park r9에 r10(offset 0, r10의 1Byte)을 로드 한다.
		@ r10 --> .word	input_data_end - 4	@ r10 (inflated size location)
		@ input_data_end : ./arch/arm/boot/compressed/piggy.S 마지막 줄에 있음
		ldrb	lr, [r10, #1]
		@ 20180728 je.park lr(link register)에 r10의 1byte offset 값을 로드한다.
		orr	r9, r9, lr, lsl #8
		ldrb	lr, [r10, #2]
		ldrb	r10, [r10, #3]
		orr	r9, r9, lr, lsl #16
		orr	r9, r9, r10, lsl #24
		@ 20180728 je.park Memory에 있는 값을 Endian에 맞춰서 읽어오는 코드
		@ GZIP 파일은 맨 끝에 압축 전 파일의 사이즈를 가지고 있다.
		@ Ref1 : https://e4deen.wordpress.com/2014/06/21/39/
		@ Ref2 : https://andromedarabbit.github.io/old-projects/src/zip/GzipFileFormat.html#ISIZE

#ifndef CONFIG_ZBOOT_ROM
		@ 20180728 je.park .config 파일에 정의 되어 있지 않으므로 해당 코드가 실행 됨
		/* malloc space is above the relocated stack (64k max) */
		add	sp, sp, r0
		@ 20180728 je.park sp에 (sp+r0) 값을 저장한다.
		add	r10, sp, #0x10000
		@ 20180728 je.park r10에 (sp+0x10000) 값을 저장한다.
#else
		/*
		 * With ZBOOT_ROM the bss/stack is non relocatable,
		 * but someone could still run this code from RAM,
		 * in which case our reference is _edata.
		 */
		mov	r10, r6
#endif

		mov	r5, #0			@ init dtb size to 0
		@ 20180728 je.park 아래 CONFIG_ARM_APPENDED_DTB 값은 .config에서 설정 되지 않기 때문에 아래 define 항목은 넘어감
#ifdef CONFIG_ARM_APPENDED_DTB
/*
 *   r0  = delta
 *   r2  = BSS start
 *   r3  = BSS end
 *   r4  = final kernel address (possibly with LSB set)
 *   r5  = appended dtb size (still unknown)
 *   r6  = _edata
 *   r7  = architecture ID
 *   r8  = atags/device tree pointer
 *   r9  = size of decompressed image
 *   r10 = end of this image, including  bss/stack/malloc space if non XIP
 *   r11 = GOT start
 *   r12 = GOT end
 *   sp  = stack pointer
 *
 * if there are device trees (dtb) appended to zImage, advance r10 so that the
 * dtb data will get relocated along with the kernel if necessary.
 */

		ldr	lr, [r6, #0]
#ifndef __ARMEB__
		ldr	r1, =0xedfe0dd0		@ sig is 0xd00dfeed big endian
#else
		ldr	r1, =0xd00dfeed
#endif
		cmp	lr, r1
		bne	dtb_check_done		@ not found

#ifdef CONFIG_ARM_ATAG_DTB_COMPAT
		/*
		 * OK... Let's do some funky business here.
		 * If we do have a DTB appended to zImage, and we do have
		 * an ATAG list around, we want the later to be translated
		 * and folded into the former here. No GOT fixup has occurred
		 * yet, but none of the code we're about to call uses any
		 * global variable.
		*/

		/* Get the initial DTB size */
		ldr	r5, [r6, #4]
#ifndef __ARMEB__
		/* convert to little endian */
		eor	r1, r5, r5, ror #16
		bic	r1, r1, #0x00ff0000
		mov	r5, r5, ror #8
		eor	r5, r5, r1, lsr #8
#endif
		/* 50% DTB growth should be good enough */
		add	r5, r5, r5, lsr #1
		/* preserve 64-bit alignment */
		add	r5, r5, #7
		bic	r5, r5, #7
		/* clamp to 32KB min and 1MB max */
		cmp	r5, #(1 << 15)
		movlo	r5, #(1 << 15)
		cmp	r5, #(1 << 20)
		movhi	r5, #(1 << 20)
		/* temporarily relocate the stack past the DTB work space */
		add	sp, sp, r5

		stmfd	sp!, {r0-r3, ip, lr}
		mov	r0, r8
		mov	r1, r6
		mov	r2, r5
		bl	atags_to_fdt

		/*
		 * If returned value is 1, there is no ATAG at the location
		 * pointed by r8.  Try the typical 0x100 offset from start
		 * of RAM and hope for the best.
		 */
		cmp	r0, #1
		sub	r0, r4, #TEXT_OFFSET
		bic	r0, r0, #1
		add	r0, r0, #0x100
		mov	r1, r6
		mov	r2, r5
		bleq	atags_to_fdt

		ldmfd	sp!, {r0-r3, ip, lr}
		sub	sp, sp, r5
#endif

		mov	r8, r6			@ use the appended device tree

		/*
		 * Make sure that the DTB doesn't end up in the final
		 * kernel's .bss area. To do so, we adjust the decompressed
		 * kernel size to compensate if that .bss size is larger
		 * than the relocated code.
		 */
		ldr	r5, =_kernel_bss_size
		adr	r1, wont_overwrite
		sub	r1, r6, r1
		subs	r1, r5, r1
		addhi	r9, r9, r1

		/* Get the current DTB size */
		ldr	r5, [r6, #4]
#ifndef __ARMEB__
		/* convert r5 (dtb size) to little endian */
		eor	r1, r5, r5, ror #16
		bic	r1, r1, #0x00ff0000
		mov	r5, r5, ror #8
		eor	r5, r5, r1, lsr #8
#endif

		/* preserve 64-bit alignment */
		add	r5, r5, #7
		bic	r5, r5, #7

		/* relocate some pointers past the appended dtb */
		add	r6, r6, r5
		add	r10, r10, r5
		add	sp, sp, r5
dtb_check_done:
#endif

		@ 20180728 je.park 위 define  CONFIG_ARM_APPENDED_DTB 구문 타지 않음
/*
 * Check to see if we will overwrite ourselves.
 *   r4  = final kernel address (possibly with LSB set)
 *   r9  = size of decompressed image
 *   r10 = end of this image, including  bss/stack/malloc space if non XIP
 * We basically want:
 *   r4 - 16k page directory >= r10 -> OK
 *   r4 + image length <= address of wont_overwrite -> OK
 * Note: the possible LSB in r4 is harmless here.
 */
		@ 20180728 je.park, 16384 = 16 * 1024
		@ 20180728 je.park, 앞서 r10에 sp + 0x10000 값을 저장함
		add	r10, r10, #16384
		cmp	r4, r10
		bhs	wont_overwrite @ 180804 by.choi 겹치지 않으면 점프
		@ 20180728 je.park, b(branch)hs(carry set), carry가 set인 경우 branch
		add	r10, r4, r9
		adr	r9, wont_overwrite
		cmp	r10, r9
		bls	wont_overwrite @ 180804 by.choi 겹치지 않으면 점프
		@ 20180728 je.park, wont_overwrite는 현재 Code(head.S) 파일에 있음
		@ 20180728 je.park, Overwrite 여부를 점검, 실행 시 Overwrite를 하기 때문에 계산 결과들이 wont_overwrite lable로 branch 안하는 것 처럼 보임
		@ Ref : https://www.slideshare.net/HelloJaewon/linux-kernel-heads-restart-label

/*
 * Relocate ourselves past the end of the decompressed kernel.
 *   r6  = _edata
 *   r10 = end of the decompressed kernel
 * Because we always copy ahead, we need to do it from the end and go
 * backward in case the source and destination overlap.
 */
		/*
		 * Bump to the next 256-byte boundary with the size of
		 * the relocation code added. This avoids overwriting
		 * ourself when the offset is small.
		 */
		add	r10, r10, #((reloc_code_end - restart + 256) & ~255)
		@ 20180728 je.park, reloc_code_end,restart lable의 주소값?을 예측하기 힘듬
		@ 20180728 je.park, 차 후 lable 주소 참고 하여 다시 보기로 함
		bic	r10, r10, #255

		/* Get start of code we want to copy and align it down. */
		adr	r5, restart
		bic	r5, r5, #31
		@ 20180728 je.park, bic -> 하위 5bit(0 ~ 4)를 0으로 초기화

/* Relocate the hyp vector base if necessary */
		@ 20180728 je.park, .config 파일에 CONFIG_ARM_VIRT_EXT 정의되어 있음
#ifdef CONFIG_ARM_VIRT_EXT
		mrs	r0, spsr
		@ 20180728 je.park, spsr의 값을 r0로 복사
		and	r0, r0, #MODE_MASK
		@ 20180728 je.park, MODE_MASK	0x0000001f
		cmp	r0, #HYP_MODE
		@ 20180728 je.park, HYP_MODE	0x0000001a
		bne	1f
		@ 20180728 je.park, Z Flag가 0일 경우 Branch

		/*
		 * Compute the address of the hyp vectors after relocation.
		 * This requires some arithmetic since we cannot directly
		 * reference __hyp_stub_vectors in a PC-relative way.
		 * Call __hyp_set_vectors with the new address so that we
		 * can HVC again after the copy.
		 */
0:		adr	r0, 0b
		movw	r1, #:lower16:__hyp_stub_vectors - 0b
		movt	r1, #:upper16:__hyp_stub_vectors - 0b
		add	r0, r0, r1
		sub	r0, r0, r5
		add	r0, r0, r10
		bl	__hyp_set_vectors
1:
#endif
		@ 20180728 k15b_last, 14주차

		sub	r9, r6, r5		@ size to copy @ 180804 by.choi r6는 _edata(zimage 상단) r5는 restart주소를 32byte allign한 값
		add	r9, r9, #31		@ rounded up to a multiple
		bic	r9, r9, #31		@ ... of 32 bytes @ 180804 by.choi 32byte allign, 현재 r9는 decompressed 사이즈
		add	r6, r9, r5 @ 180804 by.choi zimage의 끝 위치
		add	r9, r9, r10 @ 180804 by.choi relocation될 끝 위치

1:		ldmdb	r6!, {r0 - r3, r10 - r12, lr}
		cmp	r6, r5
		stmdb	r9!, {r0 - r3, r10 - r12, lr} @ 180804 by.choi r6 ~ restart 까지를 r9 위치로 감소하면서 복사
		bhi	1b @ 180804 by.choi C and !Z인 경우(r6 > r5)

		/* Preserve offset to relocated code. */
		sub	r6, r9, r6 @ 180804 by.choi 원래 zimage와 재배치된 zimage의 offset

#ifndef CONFIG_ZBOOT_ROM
		/* cache_clean_flush may use the stack, so relocate it */
		add	sp, sp, r6 @ 180804 by.choi sp의 값을 offset만큼 증가시킴
#endif

		bl	cache_clean_flush @ 180804 by.choi cache_clean_flush로 점프, link register에 다음 실행주소 저장

		badr	r0, restart
		add	r0, r0, r6
		mov	pc, r0

wont_overwrite:
/*
 * If delta is zero, we are running at the address we were linked at.
 *   r0  = delta
 *   r2  = BSS start
 *   r3  = BSS end
 *   r4  = kernel execution address (possibly with LSB set)
 *   r5  = appended dtb size (0 if not present)
 *   r7  = architecture ID
 *   r8  = atags pointer
 *   r11 = GOT start
 *   r12 = GOT end
 *   sp  = stack pointer
 */
		orrs	r1, r0, r5
		beq	not_relocated

		add	r11, r11, r0
		add	r12, r12, r0

#ifndef CONFIG_ZBOOT_ROM
		/*
		 * If we're running fully PIC === CONFIG_ZBOOT_ROM = n,
		 * we need to fix up pointers into the BSS region.
		 * Note that the stack pointer has already been fixed up.
		 */
		add	r2, r2, r0
		add	r3, r3, r0

		/*
		 * Relocate all entries in the GOT table.
		 * Bump bss entries to _edata + dtb size
		 */
1:		ldr	r1, [r11, #0]		@ relocate entries in the GOT
		add	r1, r1, r0		@ This fixes up C references
		cmp	r1, r2			@ if entry >= bss_start &&
		cmphs	r3, r1			@       bss_end > entry
		addhi	r1, r1, r5		@    entry += dtb size
		str	r1, [r11], #4		@ next entry
		cmp	r11, r12
		blo	1b

		/* bump our bss pointers too */
		add	r2, r2, r5
		add	r3, r3, r5

#else

		/*
		 * Relocate entries in the GOT table.  We only relocate
		 * the entries that are outside the (relocated) BSS region.
		 */
1:		ldr	r1, [r11, #0]		@ relocate entries in the GOT
		cmp	r1, r2			@ entry < bss_start ||
		cmphs	r3, r1			@ _end < entry
		addlo	r1, r1, r0		@ table.  This fixes up the
		str	r1, [r11], #4		@ C references.
		cmp	r11, r12
		blo	1b
#endif

not_relocated:	mov	r0, #0
1:		str	r0, [r2], #4		@ clear bss
		str	r0, [r2], #4
		str	r0, [r2], #4
		str	r0, [r2], #4
		cmp	r2, r3
		blo	1b

		/*
		 * Did we skip the cache setup earlier?
		 * That is indicated by the LSB in r4.
		 * Do it now if so.
		 */
		tst	r4, #1
		bic	r4, r4, #1
		blne	cache_on

/*
 * The C runtime environment should now be setup sufficiently.
 * Set up some pointers, and start decompressing.
 *   r4  = kernel execution address
 *   r7  = architecture ID
 *   r8  = atags pointer
 */
		mov	r0, r4
		mov	r1, sp			@ malloc space above stack
		add	r2, sp, #0x10000	@ 64k max
		mov	r3, r7
		bl	decompress_kernel
		bl	cache_clean_flush
		bl	cache_off
		mov	r1, r7			@ restore architecture number
		mov	r2, r8			@ restore atags pointer

#ifdef CONFIG_ARM_VIRT_EXT
		mrs	r0, spsr		@ Get saved CPU boot mode
		and	r0, r0, #MODE_MASK
		cmp	r0, #HYP_MODE		@ if not booted in HYP mode...
		bne	__enter_kernel		@ boot kernel directly

		adr	r12, .L__hyp_reentry_vectors_offset
		ldr	r0, [r12]
		add	r0, r0, r12

		bl	__hyp_set_vectors
		__HVC(0)			@ otherwise bounce to hyp mode

		b	.			@ should never be reached

		.align	2
.L__hyp_reentry_vectors_offset:	.long	__hyp_reentry_vectors - .
#else
		b	__enter_kernel
#endif

		.align	2
		.type	LC0, #object
LC0:		.word	LC0			@ r1
		.word	__bss_start		@ r2
		.word	_end			@ r3
		.word	_edata			@ r6
		.word	input_data_end - 4	@ r10 (inflated size location)
		.word	_got_start		@ r11
		.word	_got_end		@ ip
		.word	.L_user_stack_end	@ sp
		.word	_end - restart + 16384 + 1024*1024
		.size	LC0, . - LC0

#ifdef CONFIG_ARCH_RPC
		.globl	params
params:		ldr	r0, =0x10000100		@ params_phys for RPC
		mov	pc, lr
		.ltorg
		.align
#endif

/*
 * Turn on the cache.  We need to setup some page tables so that we
 * can have both the I and D caches on.
 *
 * We place the page tables 16k down from the kernel execution address,
 * and we hope that nothing else is using it.  If we're using it, we
 * will go pop!
 *
 * On entry,
 *  r4 = kernel execution address
 *  r7 = architecture number
 *  r8 = atags pointer
 * On exit,
 *  r0, r1, r2, r3, r9, r10, r12 corrupted
 * This routine must preserve:
 *  r4, r7, r8
 */
		.align	5				@ 기존에는 4byte를 1word로 주소를 접근했는데 이제는 2^5byte를 1word로 한다.  
cache_on:	mov	r3, #8			@ cache_on function
								@ r3에 8을 저장
		b	call_cache_fn		@ 

/*
 * Initialize the highest priority protection region, PR7
 * to cover all 32bit address and cacheable and bufferable.
 */
__armv4_mpu_cache_on:
		mov	r0, #0x3f		@ 4G, the whole
		mcr	p15, 0, r0, c6, c7, 0	@ PR7 Area Setting
		mcr 	p15, 0, r0, c6, c7, 1

		mov	r0, #0x80		@ PR7
		mcr	p15, 0, r0, c2, c0, 0	@ D-cache on
		mcr	p15, 0, r0, c2, c0, 1	@ I-cache on
		mcr	p15, 0, r0, c3, c0, 0	@ write-buffer on

		mov	r0, #0xc000
		mcr	p15, 0, r0, c5, c0, 1	@ I-access permission
		mcr	p15, 0, r0, c5, c0, 0	@ D-access permission

		mov	r0, #0
		mcr	p15, 0, r0, c7, c10, 4	@ drain write buffer
		mcr	p15, 0, r0, c7, c5, 0	@ flush(inval) I-Cache
		mcr	p15, 0, r0, c7, c6, 0	@ flush(inval) D-Cache
		mrc	p15, 0, r0, c1, c0, 0	@ read control reg
						@ ...I .... ..D. WC.M
		orr	r0, r0, #0x002d		@ .... .... ..1. 11.1
		orr	r0, r0, #0x1000		@ ...1 .... .... ....

		mcr	p15, 0, r0, c1, c0, 0	@ write control reg

		mov	r0, #0
		mcr	p15, 0, r0, c7, c5, 0	@ flush(inval) I-Cache
		mcr	p15, 0, r0, c7, c6, 0	@ flush(inval) D-Cache
		mov	pc, lr

__armv3_mpu_cache_on:
		mov	r0, #0x3f		@ 4G, the whole
		mcr	p15, 0, r0, c6, c7, 0	@ PR7 Area Setting

		mov	r0, #0x80		@ PR7
		mcr	p15, 0, r0, c2, c0, 0	@ cache on
		mcr	p15, 0, r0, c3, c0, 0	@ write-buffer on

		mov	r0, #0xc000
		mcr	p15, 0, r0, c5, c0, 0	@ access permission

		mov	r0, #0
		mcr	p15, 0, r0, c7, c0, 0	@ invalidate whole cache v3
		/*
		 * ?? ARMv3 MMU does not allow reading the control register,
		 * does this really work on ARMv3 MPU?
		 */
		mrc	p15, 0, r0, c1, c0, 0	@ read control reg
						@ .... .... .... WC.M
		orr	r0, r0, #0x000d		@ .... .... .... 11.1
		/* ?? this overwrites the value constructed above? */
		mov	r0, #0
		mcr	p15, 0, r0, c1, c0, 0	@ write control reg

		/* ?? invalidate for the second time? */
		mcr	p15, 0, r0, c7, c0, 0	@ invalidate whole cache v3
		mov	pc, lr

#ifdef CONFIG_CPU_DCACHE_WRITETHROUGH
#define CB_BITS 0x08
#else
#define CB_BITS 0x0c
#endif

__setup_mmu:	sub	r3, r4, #16384		@ Page directory size 180707 by.choi r4는 cache_on에서 설정 r4(0x00008000) - #16384 = 16384(0x00004000) 페이지 디렉토리 크기는 16K
		bic	r3, r3, #0xff		@ Align the pointer 180707 by.choi r3 = r3 & ^#0xff(0x00004000 = 0x00004000 & 0xffffff00)
		bic	r3, r3, #0x3f00     @ 180707 by.choi r3 = r3 & ^#0x3f00(0x00004000 = 0x00004000 & 0xffffc0ff) 
/*
 * Initialise the page tables, turning on the cacheable and bufferable
 * bits for the RAM area only.
 */
		mov	r0, r3  @ 180707 by.choi r0=r3(0x00004000)
		mov	r9, r0, lsr #18 @ 180707 by.choi lsr는 logical shift right FFFFFFFF이면 00003FFF, 0x00004000이면 0x00000000
		mov	r9, r9, lsl #18		@ start of RAM 180707 by.choi logical shift left 0003FFF면 FFFC0000, 0x00000000 이면 0x0000 앞FFFC값만 남기려함
		add	r10, r9, #0x10000000	@ a reasonable RAM size 180707 by.choi r10(0x10000000 = 0x00000000 + 0x10000000) ram size:256MB
		mov	r1, #0x12		@ XN|U + section mapping 180707 by.choi r1=0x12
		orr	r1, r1, #3 << 10	@ AP=11 180707 by.choi r1(0xc12 = 10010 | 110000000000)
		add	r2, r3, #16384  @ 180707 by.choi r2(0x00008000 = 0x00004000 + 0x00004000)
1:		cmp	r1, r9			@ if virt > start of RAM 180707 by.choi r1 > r9 cpsr Z=0 C=1
		cmphs	r10, r1			@   && end of RAM > virt 180707 by.choi C=1이므로 실행 r10 > r1 cpsr C=1
		bic	r1, r1, #0x1c		@ clear XN|U + C + B 180707 by.choi r1(0xc02 = 0xc12 & ^0x1c) 
		orrlo	r1, r1, #0x10		@ Set XN|U for non-RAM
		orrhs	r1, r1, r6		@ set RAM section settings 180707 by.choi C=1이므로 실행, r6=0xE, r1(0xc0e = 0xc02 | 0xE)
		str	r1, [r0], #4		@ 1:1 mapping 180707 by.choi r0에r1을 저장한후에 r0를 4증가
		add	r1, r1, #1048576 @ 180707 by.choi r1을 1MB 늘림, r1=0x100c0E
		teq	r0, r2 @ 180707 by.choi teq는 exclusive or, if r0==r2이면 Z=1  
		bne	1b @ 180707 by.choi Z=0일떄 실행, 반복적으로 수행해서 페이지테이블을 초기화
/*
 * If ever we are running from Flash, then we surely want the cache
 * to be enabled also for our execution instance...  We map 2MB of it
 * so there is no map overlap problem for up to 1 MB compressed kernel.
 * If the execution is in RAM then we would only be duplicating the above.
 */
		orr	r1, r6, #0x04		@ ensure B is set for this 180707 by.choi r1(0xE = 0xE | 0x04)
		orr	r1, r1, #3 << 10 @ 180707 by.choi r1(c0e = 0xe | 110000000000)
		mov	r2, pc 
		mov	r2, r2, lsr #20 @ 180707 by.choi pc에서 1MB 이하를 날림r2 = PC >> 20
		orr	r1, r1, r2, lsl #20 @ 180707 by.choi r1(???????00c0e = ???????00000 + c0e)
		add	r0, r3, r2, lsl #2 @ 180707 by.choi r0 = 0x4000 + PC >> 20 << 2
		str	r1, [r0], #4 @ 180707 by.choi r0에 r1값을 저장한 후 r0를 4증가
		add	r1, r1, #1048576 @ 180707 by.choi r1을 1MB 늘림
		str	r1, [r0] @ 180707 by.choi r1값을 r0에 저장
		mov	pc, lr @ 180707 by.choi pc에lr을 넣음
		@ 180707 k15b_last by.choi 다음주에 더 보기로함
ENDPROC(__setup_mmu)

@ Enable unaligned access on v6, to allow better code generation
@ for the decompressor C code:
__armv6_mmu_cache_on:
		mrc	p15, 0, r0, c1, c0, 0	@ read SCTLR
		bic	r0, r0, #2		@ A (no unaligned access fault)
		orr	r0, r0, #1 << 22	@ U (v6 unaligned access model)
		mcr	p15, 0, r0, c1, c0, 0	@ write SCTLR
		b	__armv4_mmu_cache_on

__arm926ejs_mmu_cache_on:
#ifdef CONFIG_CPU_DCACHE_WRITETHROUGH
		mov	r0, #4			@ put dcache in WT mode
		mcr	p15, 7, r0, c15, c0, 0
#endif

__armv4_mmu_cache_on:
		mov	r12, lr
#ifdef CONFIG_MMU
		mov	r6, #CB_BITS | 0x12	@ U
		bl	__setup_mmu
		mov	r0, #0
		mcr	p15, 0, r0, c7, c10, 4	@ drain write buffer
		mcr	p15, 0, r0, c8, c7, 0	@ flush I,D TLBs
		mrc	p15, 0, r0, c1, c0, 0	@ read control reg
		orr	r0, r0, #0x5000		@ I-cache enable, RR cache replacement
		orr	r0, r0, #0x0030
 ARM_BE8(	orr	r0, r0, #1 << 25 )	@ big-endian page tables
		bl	__common_mmu_cache_on
		mov	r0, #0
		mcr	p15, 0, r0, c8, c7, 0	@ flush I,D TLBs
#endif
		mov	pc, r12

__armv7_mmu_cache_on:
		mov	r12, lr @ 180707 by.choi r12에 lr값을 넣음
#ifdef CONFIG_MMU @ 180707 by.choi .config에 정의됨
		mrc	p15, 0, r11, c0, c1, 4	@ read ID_MMFR0 180707 by.choi memory model feature정보를 r11에 가져온다.
		tst	r11, #0xf		@ VMSA 180707 by.choi if ID_MMFR0 지원안하면 Z=1, 지원하면 Z=0
		movne	r6, #CB_BITS | 0x02	@ !XN 180707 cpsr Z=0이라서 실행,r6 =  #CB_BITS | 0x2 = 0x0E
		blne	__setup_mmu @ 180707 by.choi cpsr Z=0이라서 실행, lr에 다음 명령어 주소를 넣고 점프함
		mov	r0, #0
		mcr	p15, 0, r0, c7, c10, 4	@ drain write buffer 
									@ 18.07.14 bj.jung write buffer 비워줌(?) (0으로 채움), cache 사용 중이면 완료 될 떄까지 기다림. 
		tst	r11, #0xf		@ VMSA 180707 by.choi if ID_MMFR0 지원안하면 Z=1, 지원하면 Z=0
							@ Virtual Memory System Architecture, MMU 여부 판단

		mcrne	p15, 0, r0, c8, c7, 0	@ flush I,D TLBs
#endif
		mrc	p15, 0, r0, c1, c0, 0	@ read control reg
		bic	r0, r0, #1 << 28	@ clear SCTLR.TRE  
								@ 18.07.14 bj.jung TEX 비트를 모두 OS용으로 사용하지 않고, MMU에 사용, (TEX, C, B 에 따라 Page Table Format 변경) 
		orr	r0, r0, #0x5000		@ I-cache enable, RR cache replacement
		orr	r0, r0, #0x003c		@ write buffer 18.07.14 bj.jung write buffer data 캐쉬 enable 설정, RAO/SBOP로 reserved 영역 값을 1로 설정해야 함.
		bic	r0, r0, #2		@ A (no unaligned access fault)
		orr	r0, r0, #1 << 22	@ U (v6 unaligned access model)
						@ (needed for ARM1176)
#ifdef CONFIG_MMU
 ARM_BE8(	orr	r0, r0, #1 << 25 )	@ big-endian page tables
		mrcne   p15, 0, r6, c2, c0, 2   @ read ttb control reg
		orrne	r0, r0, #1		@ MMU enabled
		movne	r1, #0xfffffffd		@ domain 0 = client
		bic     r6, r6, #1 << 31        @ 32-bit translation system
										@ 18.07.14 bj.jung TTBCR.EAE (Extended Address Enable) bit를 0으로 세팅, 1일 경우 레지스터 활용이 달라짐.
		bic     r6, r6, #(7 << 0) | (1 << 4)	@ use only ttbr0 
												@ 18.07.14 bj.jung TLB MISS 일때, TTBR0를 사용
		mcrne	p15, 0, r3, c2, c0, 0	@ load page table pointer TTRB0 값을 0x4000으로 설정
		mcrne	p15, 0, r1, c3, c0, 0	@ load domain access control
										@ 18.07.14 bj.jung D0(도메인0) client, D1 ~ D15 Manager 모드
		mcrne   p15, 0, r6, c2, c0, 2   @ load ttb control
										@ 18.07.14 bj.jung TTBCR 재설정 
#endif
		mcr	p15, 0, r0, c7, c5, 4	@ ISB
		mcr	p15, 0, r0, c1, c0, 0	@ load control register
		mrc	p15, 0, r0, c1, c0, 0	@ and read it back
		mov	r0, #0
		mcr	p15, 0, r0, c7, c5, 4	@ ISB
									@ 18.07.14 bj.jung control register 로드만 수행하고 파이프라인 플러시(?)
		mov	pc, r12

									@ 180714 k15b_last bj.jung

__fa526_cache_on:
		mov	r12, lr
		mov	r6, #CB_BITS | 0x12	@ U
		bl	__setup_mmu
		mov	r0, #0
		mcr	p15, 0, r0, c7, c7, 0	@ Invalidate whole cache
		mcr	p15, 0, r0, c7, c10, 4	@ drain write buffer
		mcr	p15, 0, r0, c8, c7, 0	@ flush UTLB
		mrc	p15, 0, r0, c1, c0, 0	@ read control reg
		orr	r0, r0, #0x1000		@ I-cache enable
		bl	__common_mmu_cache_on
		mov	r0, #0
		mcr	p15, 0, r0, c8, c7, 0	@ flush UTLB
		mov	pc, r12

__common_mmu_cache_on:
#ifndef CONFIG_THUMB2_KERNEL
#ifndef DEBUG
		orr	r0, r0, #0x000d		@ Write buffer, mmu
#endif
		mov	r1, #-1
		mcr	p15, 0, r3, c2, c0, 0	@ load page table pointer
		mcr	p15, 0, r1, c3, c0, 0	@ load domain access control
		b	1f
		.align	5			@ cache line aligned
1:		mcr	p15, 0, r0, c1, c0, 0	@ load control register
		mrc	p15, 0, r0, c1, c0, 0	@ and read it back to
		sub	pc, lr, r0, lsr #32	@ properly flush pipeline
#endif

#define PROC_ENTRY_SIZE (4*5)

/*
 * Here follow the relocatable cache support functions for the
 * various processors.  This is a generic hook for locating an
 * entry and jumping to an instruction at the specified offset
 * from the start of the block.  Please note this is all position
 * independent code.
 *
 *  r1  = corrupted
 *  r2  = corrupted
 *  r3  = block offset
 *  r9  = corrupted
 *  r12 = corrupted
 */

call_cache_fn:	adr	r12, proc_types                   	@ 180630 dh.park proc_types의 주소를 r12에 복사한다.
#ifdef CONFIG_CPU_CP15									@ 180630 dh.park .config 파일에 정의됨.
		mrc	p15, 0, r9, c0, c0	@ get processor ID	  	@ 180630 dh.park r9에 프로세서 ID를 가져온다.
#elif defined(CONFIG_CPU_V7M)
		/*
		 * On v7-M the processor id is located in the V7M_SCB_CPUID
		 * register, but as cache handling is IMPLEMENTATION DEFINED on
		 * v7-M (if existant at all) we just return early here.
		 * If V7M_SCB_CPUID were used the cpu ID functions (i.e.
		 * __armv7_mmu_cache_{on,off,flush}) would be selected which
		 * use cp15 registers that are not implemented on v7-M.
		 */
		bx	lr
#else
		ldr	r9, =CONFIG_PROCESSOR_ID					@ 180707 by.choi 실행안함
#endif
1:		ldr	r1, [r12, #0]		@ get value				@ 180630 dh.park proc_types 구조체의 0번재 값을 r1으로 가져온다. 
		ldr	r2, [r12, #4]		@ get mask				@ 180630 dh.park proc_tyoes 구조체의 1번째 값을 r2로 가져온다.
		eor	r1, r1, r9		@ (real ^ match)			@ 180630 dh.park 0x41000000 ^ 0x00007700 (프로세서 ID)를 비교해서 r1 복사한다 => 0x41007700 값이 나온다.
		tst	r1, r2			@       & mask				@ 180630 dh.park 0x41007700 & 0xff00f000 -> 0x41007000 이 나온다. cpsr의 값을  n=0, z=0, c=0 로 업데이트 한다. 
 ARM(		addeq	pc, r12, r3		) @ call cache function 
														@ 180630 dh.park arm 이면 실행한다. z값이 0이기 때문에 add 연산을 하지 않는다.
 THUMB(		addeq	r12, r3			)
 THUMB(		moveq	pc, r12			) @ call cache function
		add	r12, r12, #PROC_ENTRY_SIZE					@ 180630 dh.park r12에 0xffffff00 + (4*5) -> 0xffffff14 값을 복사한다. #PROC_ENTRY_SIZE는4*5
		b	1b @ 180707 by.choi CPU ID가 일치할때까지 비교함, 일치하면 mov pc, lr 실행
			   @ 180707 by.choi lr값은268line
@ 180630 k15b_last dh.park 하지만 더 봐야해요. 
/*
 * Table for cache operations.  This is basically:
 *   - CPU ID match
 *   - CPU ID mask
 *   - 'cache on' method instruction
 *   - 'cache off' method instruction
 *   - 'cache flush' method instruction
 *
 * We match an entry using: ((real_id ^ match) & mask) == 0
 *
 * Writethrough caches generally only need 'on' and 'off'
 * methods.  Writeback caches _must_ have the flush method
 * defined.
 */
		.align	2
		.type	proc_types,#object
proc_types:
		.word	0x41000000		@ old ARM ID
		.word	0xff00f000
		mov	pc, lr
 THUMB(		nop				)
		mov	pc, lr
 THUMB(		nop				)
		mov	pc, lr
 THUMB(		nop				)

		.word	0x41007000		@ ARM7/710
		.word	0xfff8fe00
		mov	pc, lr
 THUMB(		nop				)
		mov	pc, lr
 THUMB(		nop				)
		mov	pc, lr
 THUMB(		nop				)

		.word	0x41807200		@ ARM720T (writethrough)
		.word	0xffffff00
		W(b)	__armv4_mmu_cache_on
		W(b)	__armv4_mmu_cache_off
		mov	pc, lr
 THUMB(		nop				)

		.word	0x41007400		@ ARM74x
		.word	0xff00ff00
		W(b)	__armv3_mpu_cache_on
		W(b)	__armv3_mpu_cache_off
		W(b)	__armv3_mpu_cache_flush
		
		.word	0x41009400		@ ARM94x
		.word	0xff00ff00
		W(b)	__armv4_mpu_cache_on
		W(b)	__armv4_mpu_cache_off
		W(b)	__armv4_mpu_cache_flush

		.word	0x41069260		@ ARM926EJ-S (v5TEJ)
		.word	0xff0ffff0
		W(b)	__arm926ejs_mmu_cache_on
		W(b)	__armv4_mmu_cache_off
		W(b)	__armv5tej_mmu_cache_flush

		.word	0x00007000		@ ARM7 IDs
		.word	0x0000f000
		mov	pc, lr
 THUMB(		nop				)
		mov	pc, lr
 THUMB(		nop				)
		mov	pc, lr
 THUMB(		nop				)

		@ Everything from here on will be the new ID system.

		.word	0x4401a100		@ sa110 / sa1100
		.word	0xffffffe0
		W(b)	__armv4_mmu_cache_on
		W(b)	__armv4_mmu_cache_off
		W(b)	__armv4_mmu_cache_flush

		.word	0x6901b110		@ sa1110
		.word	0xfffffff0
		W(b)	__armv4_mmu_cache_on
		W(b)	__armv4_mmu_cache_off
		W(b)	__armv4_mmu_cache_flush

		.word	0x56056900
		.word	0xffffff00		@ PXA9xx
		W(b)	__armv4_mmu_cache_on
		W(b)	__armv4_mmu_cache_off
		W(b)	__armv4_mmu_cache_flush

		.word	0x56158000		@ PXA168
		.word	0xfffff000
		W(b)	__armv4_mmu_cache_on
		W(b)	__armv4_mmu_cache_off
		W(b)	__armv5tej_mmu_cache_flush

		.word	0x56050000		@ Feroceon
		.word	0xff0f0000
		W(b)	__armv4_mmu_cache_on
		W(b)	__armv4_mmu_cache_off
		W(b)	__armv5tej_mmu_cache_flush

#ifdef CONFIG_CPU_FEROCEON_OLD_ID
		/* this conflicts with the standard ARMv5TE entry */
		.long	0x41009260		@ Old Feroceon
		.long	0xff00fff0
		b	__armv4_mmu_cache_on
		b	__armv4_mmu_cache_off
		b	__armv5tej_mmu_cache_flush
#endif

		.word	0x66015261		@ FA526
		.word	0xff01fff1
		W(b)	__fa526_cache_on
		W(b)	__armv4_mmu_cache_off
		W(b)	__fa526_cache_flush

		@ These match on the architecture ID

		.word	0x00020000		@ ARMv4T
		.word	0x000f0000
		W(b)	__armv4_mmu_cache_on
		W(b)	__armv4_mmu_cache_off
		W(b)	__armv4_mmu_cache_flush

		.word	0x00050000		@ ARMv5TE
		.word	0x000f0000
		W(b)	__armv4_mmu_cache_on
		W(b)	__armv4_mmu_cache_off
		W(b)	__armv4_mmu_cache_flush

		.word	0x00060000		@ ARMv5TEJ
		.word	0x000f0000
		W(b)	__armv4_mmu_cache_on
		W(b)	__armv4_mmu_cache_off
		W(b)	__armv5tej_mmu_cache_flush

		.word	0x0007b000		@ ARMv6
		.word	0x000ff000
		W(b)	__armv6_mmu_cache_on
		W(b)	__armv4_mmu_cache_off
		W(b)	__armv6_mmu_cache_flush

		.word	0x000f0000		@ new CPU Id
		.word	0x000f0000
		W(b)	__armv7_mmu_cache_on @ 180707 by.choi cache_on에서 점프함 r3=8
		W(b)	__armv7_mmu_cache_off 
		W(b)	__armv7_mmu_cache_flush @ 180804 by.choi cache_clean_flush에서 점프함 r3=16

		.word	0			@ unrecognised type
		.word	0
		mov	pc, lr
 THUMB(		nop				)
		mov	pc, lr
 THUMB(		nop				)
		mov	pc, lr
 THUMB(		nop				)

		.size	proc_types, . - proc_types

		/*
		 * If you get a "non-constant expression in ".if" statement"
		 * error from the assembler on this line, check that you have
		 * not accidentally written a "b" instruction where you should
		 * have written W(b).
		 */
		.if (. - proc_types) % PROC_ENTRY_SIZE != 0
		.error "The size of one or more proc_types entries is wrong."
		.endif

/*
 * Turn off the Cache and MMU.  ARMv3 does not support
 * reading the control register, but ARMv4 does.
 *
 * On exit,
 *  r0, r1, r2, r3, r9, r12 corrupted
 * This routine must preserve:
 *  r4, r7, r8
 */
		.align	5
cache_off:	mov	r3, #12			@ cache_off function
		b	call_cache_fn

__armv4_mpu_cache_off:
		mrc	p15, 0, r0, c1, c0
		bic	r0, r0, #0x000d
		mcr	p15, 0, r0, c1, c0	@ turn MPU and cache off
		mov	r0, #0
		mcr	p15, 0, r0, c7, c10, 4	@ drain write buffer
		mcr	p15, 0, r0, c7, c6, 0	@ flush D-Cache
		mcr	p15, 0, r0, c7, c5, 0	@ flush I-Cache
		mov	pc, lr

__armv3_mpu_cache_off:
		mrc	p15, 0, r0, c1, c0
		bic	r0, r0, #0x000d
		mcr	p15, 0, r0, c1, c0, 0	@ turn MPU and cache off
		mov	r0, #0
		mcr	p15, 0, r0, c7, c0, 0	@ invalidate whole cache v3
		mov	pc, lr

__armv4_mmu_cache_off:
#ifdef CONFIG_MMU
		mrc	p15, 0, r0, c1, c0
		bic	r0, r0, #0x000d
		mcr	p15, 0, r0, c1, c0	@ turn MMU and cache off
		mov	r0, #0
		mcr	p15, 0, r0, c7, c7	@ invalidate whole cache v4
		mcr	p15, 0, r0, c8, c7	@ invalidate whole TLB v4
#endif
		mov	pc, lr

__armv7_mmu_cache_off:
		mrc	p15, 0, r0, c1, c0
#ifdef CONFIG_MMU
		bic	r0, r0, #0x000d
#else
		bic	r0, r0, #0x000c
#endif
		mcr	p15, 0, r0, c1, c0	@ turn MMU and cache off
		mov	r12, lr
		bl	__armv7_mmu_cache_flush
		mov	r0, #0
#ifdef CONFIG_MMU
		mcr	p15, 0, r0, c8, c7, 0	@ invalidate whole TLB
#endif
		mcr	p15, 0, r0, c7, c5, 6	@ invalidate BTC
		mcr	p15, 0, r0, c7, c10, 4	@ DSB
		mcr	p15, 0, r0, c7, c5, 4	@ ISB
		mov	pc, r12

/*
 * Clean and flush the cache to maintain consistency.
 *
 * On exit,
 *  r1, r2, r3, r9, r10, r11, r12 corrupted
 * This routine must preserve:
 *  r4, r6, r7, r8
 */
		.align	5
cache_clean_flush:
		mov	r3, #16
		b	call_cache_fn

__armv4_mpu_cache_flush:
		tst	r4, #1
		movne	pc, lr
		mov	r2, #1
		mov	r3, #0
		mcr	p15, 0, ip, c7, c6, 0	@ invalidate D cache
		mov	r1, #7 << 5		@ 8 segments
1:		orr	r3, r1, #63 << 26	@ 64 entries
2:		mcr	p15, 0, r3, c7, c14, 2	@ clean & invalidate D index
		subs	r3, r3, #1 << 26
		bcs	2b			@ entries 63 to 0
		subs 	r1, r1, #1 << 5
		bcs	1b			@ segments 7 to 0

		teq	r2, #0
		mcrne	p15, 0, ip, c7, c5, 0	@ invalidate I cache
		mcr	p15, 0, ip, c7, c10, 4	@ drain WB
		mov	pc, lr
		
__fa526_cache_flush:
		tst	r4, #1
		movne	pc, lr
		mov	r1, #0
		mcr	p15, 0, r1, c7, c14, 0	@ clean and invalidate D cache
		mcr	p15, 0, r1, c7, c5, 0	@ flush I cache
		mcr	p15, 0, r1, c7, c10, 4	@ drain WB
		mov	pc, lr

__armv6_mmu_cache_flush:
		mov	r1, #0
		tst	r4, #1
		mcreq	p15, 0, r1, c7, c14, 0	@ clean+invalidate D
		mcr	p15, 0, r1, c7, c5, 0	@ invalidate I+BTB
		mcreq	p15, 0, r1, c7, c15, 0	@ clean+invalidate unified
		mcr	p15, 0, r1, c7, c10, 4	@ drain WB
		mov	pc, lr

__armv7_mmu_cache_flush:
		tst	r4, #1 @ 180804 by.choi r4=0x8000
		bne	iflush @ 180804 by.choi Z=1이므로 실행안됨
		mrc	p15, 0, r10, c0, c1, 5	@ read ID_MMFR1
		tst	r10, #0xf << 16		@ hierarchical cache (ARMv7) @ 180804 by.choi 라즈베리파이3는 지원함, 지원하면 값이 0
		mov	r10, #0
		beq	hierarchical @ 180804 by.choi Z=1이므로 점프
		mcr	p15, 0, r10, c7, c14, 0	@ clean+invalidate D
		b	iflush
hierarchical:
		mcr	p15, 0, r10, c7, c10, 5	@ DMB @ 180804 by.choi r10=0 memory 작업이 완료할 때까지 기다린다.
		stmfd	sp!, {r0-r7, r9-r11} @ 180804 by.choi r0~r7, r9~r11값을 st에 넣는다. 
		mrc	p15, 1, r0, c0, c0, 1	@ read clidr
		ands	r3, r0, #0x7000000	@ extract loc from clidr @ 180804 by.choi and, condition flag update, LOC=2으므로 Z=0
		mov	r3, r3, lsr #23		@ left align loc bit field @ 180804 by.choi r3=LOC*2, r3=4
		beq	finished		@ if loc is 0, then no need to clean @ 180804 by.choi Z=0이므로 점프안함
		mov	r10, #0			@ start clean at cache level 0 @ 180804 by.choi r10=0
		@ 20180804 k15b_last, 15주차
@ 180825 by.choi loop1은 L1 ~ L7 캐시 확인하고 설정
loop1:
		add	r2, r10, r10, lsr #1	@ work out 3x current cache level @ 180825 by.choi처음진입 r10 = 0, r2 = 0 / 두번쨰 진입 r10 = 2, r2 = 2 + 1
		mov	r1, r0, lsr r2		@ extract cache type bits from clidr @ 180825 by.choi 처음진입 r0는 r1 = r0 >> 0, 끝 3비트는 Ctype1 / 두번째 진입 r1 = r0 >> 3, 끝 3비트는 Ctype2
		and	r1, r1, #7		@ mask of the bits for current cache only @ 180825 by.choir1끝에 3비트를 남김, 라즈베리파이3는 L1, L2(L1=0b011 -> seperate i & d cache, L2=0b100 -> unified cache)만 존재, http://infocenter.arm.com/help/topic/com.arm.doc.ddi0500j/BABHCIHB.html
		cmp	r1, #2			@ see what cache we have at this level @ 180825 by.choi r1과 #2 비교, r1 < #2이면 skip 실행
		blt	skip			@ skip if no cache, or just i-cache @ 180825 by.choi signed less than, r1이 0b000, 0b001인 경우 점프, 캐시 타입 정보 http://jake.dothome.co.kr/cache_clean_flush/
		mcr	p15, 2, r10, c0, c0, 0	@ select current cache level in cssr @ 180825 by.choi http://infocenter.arm.com/help/topic/com.arm.doc.ddi0500j/BABGHJEA.html
		mcr	p15, 0, r10, c7, c5, 4	@ isb to sych the new cssr&csidr @ 180825 by.choi v8a deprecated
		mrc	p15, 1, r1, c0, c0, 0	@ read the new csidr  @ 180825 by.choi Cache Size Id Register, r1에 csidr값을 넣는다.
		and	r2, r1, #7		@ extract the length of the cache lines @ 180825 by.choi 라즈베리파이3 LineSize=0b010, r2 = 2
		add	r2, r2, #4		@ add 4 (line length offset) @ 180825 by.choi r2 = 6
		ldr	r4, =0x3ff @ 180825 by.choi r4=0x3ff
		ands	r4, r4, r1, lsr #3	@ find maximum number on the way size @ 180825 by.choi csidr의 Associativity 값을 구한다. r4=Associativity 10bit값
		clz	r5, r4			@ find bit position of way size increment @ 180825 by.choir5 = r4앞에 오는 0의 개수
		ldr	r7, =0x7fff
		ands	r7, r7, r1, lsr #13	@ extract max number of the index size @ 180825 by.choi r7=NumSets값
loop2:
		mov	r9, r4			@ create working copy of max way size @ 180825 by.choi r9=Associativity값, rpi3 기준 L1인 경우 r4=3, L2인 경우 r4=15
@ 180825 k15b_last, 16주차
loop3:
 ARM(		orr	r11, r10, r9, lsl r5	) @ factor way and cache number into r11
 ARM(		orr	r11, r11, r7, lsl r2	) @ factor index number into r11
 THUMB(		lsl	r6, r9, r5		)
 THUMB(		orr	r11, r10, r6		) @ factor way and cache number into r11
 THUMB(		lsl	r6, r7, r2		)
 THUMB(		orr	r11, r11, r6		) @ factor index number into r11
		mcr	p15, 0, r11, c7, c14, 2	@ clean & invalidate by set/way
		subs	r9, r9, #1		@ decrement the way
		bge	loop3
		subs	r7, r7, #1		@ decrement the index
		bge	loop2
skip:
		add	r10, r10, #2		@ increment cache number @ 180825 by.choi r10에 2를 더함
		cmp	r3, r10 @ 180825 by.choi r3 = 4, r3 > r10
		bgt	loop1 @ 180825 by.choi Signed greater than, r3가 크므로 loop1 점프
finished:
		ldmfd	sp!, {r0-r7, r9-r11}
		mov	r10, #0			@ switch back to cache level 0
		mcr	p15, 2, r10, c0, c0, 0	@ select current cache level in cssr
iflush:
		mcr	p15, 0, r10, c7, c10, 4	@ DSB
		mcr	p15, 0, r10, c7, c5, 0	@ invalidate I+BTB
		mcr	p15, 0, r10, c7, c10, 4	@ DSB
		mcr	p15, 0, r10, c7, c5, 4	@ ISB
		mov	pc, lr

__armv5tej_mmu_cache_flush:
		tst	r4, #1
		movne	pc, lr
1:		mrc	p15, 0, r15, c7, c14, 3	@ test,clean,invalidate D cache
		bne	1b
		mcr	p15, 0, r0, c7, c5, 0	@ flush I cache
		mcr	p15, 0, r0, c7, c10, 4	@ drain WB
		mov	pc, lr

__armv4_mmu_cache_flush:
		tst	r4, #1
		movne	pc, lr
		mov	r2, #64*1024		@ default: 32K dcache size (*2)
		mov	r11, #32		@ default: 32 byte line size
		mrc	p15, 0, r3, c0, c0, 1	@ read cache type
		teq	r3, r9			@ cache ID register present?
		beq	no_cache_id
		mov	r1, r3, lsr #18
		and	r1, r1, #7
		mov	r2, #1024
		mov	r2, r2, lsl r1		@ base dcache size *2
		tst	r3, #1 << 14		@ test M bit
		addne	r2, r2, r2, lsr #1	@ +1/2 size if M == 1
		mov	r3, r3, lsr #12
		and	r3, r3, #3
		mov	r11, #8
		mov	r11, r11, lsl r3	@ cache line size in bytes
no_cache_id:
		mov	r1, pc
		bic	r1, r1, #63		@ align to longest cache line
		add	r2, r1, r2
1:
 ARM(		ldr	r3, [r1], r11		) @ s/w flush D cache
 THUMB(		ldr     r3, [r1]		) @ s/w flush D cache
 THUMB(		add     r1, r1, r11		)
		teq	r1, r2
		bne	1b

		mcr	p15, 0, r1, c7, c5, 0	@ flush I cache
		mcr	p15, 0, r1, c7, c6, 0	@ flush D cache
		mcr	p15, 0, r1, c7, c10, 4	@ drain WB
		mov	pc, lr

__armv3_mmu_cache_flush:
__armv3_mpu_cache_flush:
		tst	r4, #1
		movne	pc, lr
		mov	r1, #0
		mcr	p15, 0, r1, c7, c0, 0	@ invalidate whole cache v3
		mov	pc, lr

/*
 * Various debugging routines for printing hex characters and
 * memory, which again must be relocatable.
 */
#ifdef DEBUG
		.align	2
		.type	phexbuf,#object
phexbuf:	.space	12
		.size	phexbuf, . - phexbuf

@ phex corrupts {r0, r1, r2, r3}
phex:		adr	r3, phexbuf
		mov	r2, #0
		strb	r2, [r3, r1]
1:		subs	r1, r1, #1
		movmi	r0, r3
		bmi	puts
		and	r2, r0, #15
		mov	r0, r0, lsr #4
		cmp	r2, #10
		addge	r2, r2, #7
		add	r2, r2, #'0'
		strb	r2, [r3, r1]
		b	1b

@ puts corrupts {r0, r1, r2, r3}
puts:		loadsp	r3, r1
1:		ldrb	r2, [r0], #1
		teq	r2, #0
		moveq	pc, lr
2:		writeb	r2, r3
		mov	r1, #0x00020000
3:		subs	r1, r1, #1
		bne	3b
		teq	r2, #'\n'
		moveq	r2, #'\r'
		beq	2b
		teq	r0, #0
		bne	1b
		mov	pc, lr
@ putc corrupts {r0, r1, r2, r3}
putc:
		mov	r2, r0
		mov	r0, #0
		loadsp	r3, r1
		b	2b

@ memdump corrupts {r0, r1, r2, r3, r10, r11, r12, lr}
memdump:	mov	r12, r0
		mov	r10, lr
		mov	r11, #0
2:		mov	r0, r11, lsl #2
		add	r0, r0, r12
		mov	r1, #8
		bl	phex
		mov	r0, #':'
		bl	putc
1:		mov	r0, #' '
		bl	putc
		ldr	r0, [r12, r11, lsl #2]
		mov	r1, #8
		bl	phex
		and	r0, r11, #7
		teq	r0, #3
		moveq	r0, #' '
		bleq	putc
		and	r0, r11, #7
		add	r11, r11, #1
		teq	r0, #7
		bne	1b
		mov	r0, #'\n'
		bl	putc
		cmp	r11, #64
		blt	2b
		mov	pc, r10
#endif

		.ltorg

#ifdef CONFIG_ARM_VIRT_EXT
.align 5
__hyp_reentry_vectors:
		W(b)	.			@ reset
		W(b)	.			@ undef
		W(b)	.			@ svc
		W(b)	.			@ pabort
		W(b)	.			@ dabort
		W(b)	__enter_kernel		@ hyp
		W(b)	.			@ irq
		W(b)	.			@ fiq
#endif /* CONFIG_ARM_VIRT_EXT */

__enter_kernel:
		mov	r0, #0			@ must be 0
 ARM(		mov	pc, r4		)	@ call kernel
 M_CLASS(	add	r4, r4, #1	)	@ enter in Thumb mode for M class
 THUMB(		bx	r4		)	@ entry point is always ARM for A/R classes

reloc_code_end:

#ifdef CONFIG_EFI_STUB
		.align	2
_start:		.long	start - .

ENTRY(efi_stub_entry)
		@ allocate space on stack for passing current zImage address
		@ and for the EFI stub to return of new entry point of
		@ zImage, as EFI stub may copy the kernel. Pointer address
		@ is passed in r2. r0 and r1 are passed through from the
		@ EFI firmware to efi_entry
		adr	ip, _start
		ldr	r3, [ip]
		add	r3, r3, ip
		stmfd	sp!, {r3, lr}
		mov	r2, sp			@ pass zImage address in r2
		bl	efi_entry

		@ Check for error return from EFI stub. r0 has FDT address
		@ or error code.
		cmn	r0, #1
		beq	efi_load_fail

		@ Preserve return value of efi_entry() in r4
		mov	r4, r0
		bl	cache_clean_flush
		bl	cache_off

		@ Set parameters for booting zImage according to boot protocol
		@ put FDT address in r2, it was returned by efi_entry()
		@ r1 is the machine type, and r0 needs to be 0
		mov	r0, #0
		mov	r1, #0xFFFFFFFF
		mov	r2, r4

		@ Branch to (possibly) relocated zImage that is in [sp]
		ldr	lr, [sp]
		ldr	ip, =start_offset
		add	lr, lr, ip
		mov	pc, lr				@ no mode switch

efi_load_fail:
		@ Return EFI_LOAD_ERROR to EFI firmware on error.
		ldr	r0, =0x80000001
		ldmfd	sp!, {ip, pc}
ENDPROC(efi_stub_entry)
#endif

		.align
		.section ".stack", "aw", %nobits
.L_user_stack:	.space	4096
.L_user_stack_end:
