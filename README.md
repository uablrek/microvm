# microvm - with firecracker and qemu-microvm

A "microvm" is a very lightweight VM. From QEMU docs:

> It’s a minimalist machine type without PCI nor ACPI support, designed for short-lived guests.

This repo describes howto create `microvm` kernels and images
compatible with [firecracker](
https://github.com/firecracker-microvm/firecracker) and
[qemu-microvm](https://qemu.readthedocs.io/en/latest/system/i386/microvm.html)


## Setup and the microvm.sh script

Prerequisites: `docker` and `kvm/qemu` are installed.

Most things are done using the `microvm.sh` script.
```
./microvm.sh        # Help printout
./microvm.sh env    # Print current environment
./microvm.sh setup  # Install items in $MICROVM_WORKSPACE
```

## Quick start

The kernel must be built locally and we use an [Alpine Linux](
https://www.alpinelinux.org/) image for this example. Images are built
with [diskim]().

```
./microvm.sh kernel_build
docker pull alpine:latest
./microvm.sh mkimage --docker-image=alpine:latest /tmp/alpine.img
./microvm.sh run_microvm --init=/bin/sh /tmp/alpine.img
# (exit with ctrl-C)
./microvm.sh run_fc --init=/bin/sh /tmp/alpine.img
# (exit with "exit")
# The /proc file system is needed for many things. In the console:
mount -t proc proc /proc
```


## Minimum kernel config

This section describes how to build a minimum kernel that can be used
with `microvm`. You may see this as "Linux kernel the hard way" :smiley:

```
builddir=/tmp/$USER/minivm
mkdir -p $builddir
export __kcfg=$builddir/kernel.conf
export __kobj=$builddir/obj
export __kernel=$builddir/bzImage
rm -f $__kcfg   # This ensures a build with an "all-no" config
./microvm.sh kernel_build
# just exit the kernel config and let it build
```

You have now built an as small Linux kernel as possible. It is totally
useless, but may be interresting for minimalists (like myself).

```
ls -lh $__kernel    # (1.4M at the time of writing)
./microvm.sh kernel_build --menuconfig
```

The configuration described below is the bare minimum to get a rootfs
and a console.

```
General setup >
[*] 64-bit kernel
Executable file formats >
  [*] Kernel support for ELF binaries
  [*] Kernel support for scripts starting with #!
Device Drivers >
  Character devices >
    Serial drivers >
	  [*] 8250/16550 and compatible serial support
	  [*]   Console on 8250/16550 and compatible serial port
  [*] Virtio drivers >
    [*]   Platform bus driver for memory mapped virtio devices
	[*]     Memory mapped virtio devices parameter parsing
  Block devices >
    [*]   Virtio block driver  
File systems >
  [*] The Extended 4 (ext4) filesystem
```

Test it:
```
ls -lh $__kernel    # (1.9M at the time of writing)
./microvm.sh run_microvm --mem=32 --init=/bin/sh /tmp/alpine.img
# (exit with ctrl-C)
./microvm.sh run_fc --mem=32 --init=/bin/sh /tmp/alpine.img
# (exit with "exit")
# In the console:
mount -t proc proc /proc
free -h
```

If you really want to learn about Linux kernel configuration, this is
a good place to start IMHO. The `microvm` is very limited so soon you
should add PCI bus support and use a more "normal" VM.

