0. cross toolchain download
	https://releases.linaro.org/components/toolchain/binaries/latest/aarch64-linux-gnu/
		환경에 맞는 것을 선택
		(x86 64비트) gcc-linaro-6.1.1-2016.08-x86_64_aarch64-linux-gnu.tar.xz

		gcc-linaro-5.3-2016.02-x86_64_aarch64-linux-gnu (테스트한 버전)
	PATH에 '압축해제한 디렉토리/bin' 등록


1. QEMU

	$ sudo apt-get build-dep qemu

		// 명령이 실패해 평소 주석처리 되어있던 deb-src 중 main이 들어간 라인들 사용
		$ vi /etc/apt/sources.list
		$ sudo apt-get update

	$ git clone git://git.qemu.org/qemu.git qemu.git
	$ cd qemu.git
	$ ./configure --target-list=aarch64-softmmu
	$ make -j8


2. BUILDROOT

	$ git clone git://git.buildroot.net/buildroot buildroot.git
	$ cd buildroot.git
	$ make menuconfig
		* Target Options -> Target Architecture(AArch64)
		* Toolchain -> Toolchain type (External toolchain)
		* Toolchain -> Toolchain (Linaro AArch64 14.02)
		* System configuration -> Run a getty (login prompt) after boot (BR2_TARGET_GENERIC_GETTY)
		* System configuration -> getty options -> TTY Port (ttyAMA0) (BR2_TARGET_GENERIC_GETTY_PORT)
		* Target Packages -> Show packages that are also provided by busybox (BR2_PACKAGE_BUSYBOX_SHOW_OTHERS)
		* Filesystem images -> cpio the root filesystem (for use as an initial RAM filesystem) (BR2_TARGET_ROOTFS_CPIO)
	$ make
	$ ls output/images/rootfs.cpio
		(결과물 첨부)


3. KERNEL

	$ git clone http://github.com/torvalds/linux.git linux.git
	$ cd linux.git
	$ export ARCH=arm64
	$ export CROSS_COMPILE=aarch64-linux-gnu-

	$ make defconfig

	// .conifg 수정
		CONFIG_CROSS_COMPILE="aarch64-linux-gnu-"                                               # needs to match your cross-compiler prefix
		CONFIG_INITRAMFS_SOURCE="run_qemu/rootfs.cpio" # points at your buildroot image
		CONFIG_NET_9P=y                                                                         # needed for virtfs mount
		CONFIG_NET_9P_VIRTIO=y

	$ make -j8


4. QEMU 실행

	/home/freestyle/Workspace/other/qemu.git/aarch64-softmmu/qemu-system-aarch64 -machine virt -cpu cortex-a57 -machine type=virt -nographic -smp 4 -m 2048 -kernel arch/arm64/boot/Image --append "console=ttyAMA0"



* 추가1. gdb로 디버깅

	- CONFIG_DEBUG_INFO
	- CONFIG_GDB_SCRIPTS
	  [참고] http://www.elinux.org/Debugging_The_Linux_Kernel_Using_Gdb


	1) qemu 실행 (-s -S 추가)

		$ /home/freestyle/Workspace/other/qemu.git/aarch64-softmmu/qemu-system-aarch64 -machine virt -cpu cortex-a57 -s -S -machine type=virt -nographic -smp 4 -m 2048 -kernel arch/arm64/boot/Image --append "console=ttyAMA0"

	2-1) gdb 사용시

		$ aarch64-linux-gnu-gdb -ex "file /home/freestyle/kernel/iamroot2016/vmlinux" -ex 'target remote localhost:1234'
			> hbreak start_kernel
			> info b
			> continue

	2-2) ddd 사용시

		$ sudo apt install ddd
		$ ddd --gdb --debugger /opt/crosstools/gcc-linaro-5.3-2016.02-x86_64_aarch64-linux-gnu/bin/aarch64-linux-gnu-gdb
			> file /home/freestyle/kernel/iamroot2016/vmlinux
			> target remote :1234
			> set print pretty
			> info b
			> continue


* 추가2. 소스 tag 생성
make ARCH=arm64 tags cscope


* 추가3. 생성된 심볼 확인
System.map
