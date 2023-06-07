# microvm - with firecracker and qemu-microvm

A "microvm" is a very lightweight VM. From QEMU docs:

> It’s a minimalist machine type without PCI nor ACPI support, designed for short-lived guests.

This repo describes howto create `microvm` kernels and images
compatible with [firecracker](
https://github.com/firecracker-microvm/firecracker) and
[qemu-microvm](https://qemu.readthedocs.io/en/latest/system/i386/microvm.html)


## Setup and the microvm.sh script

Prerequisites: `jq` and `kvm/qemu` are installed.

Most things are done using the `microvm.sh` script.
```
./microvm.sh        # Help printout
./microvm.sh env    # Print current environment
./microvm.sh setup  # Install items in $MICROVM_WORKSPACE
```


## Quick start

The kernel must be built locally and an [Alpine Linux](
https://www.alpinelinux.org/) rootfs is used by default. Images are built
with [diskim](https://github.com/lgekman/diskim).

```
./microvm.sh kernel_build
./microvm.sh mkimage /tmp/alpine.img ./templates/alpine
ls -slh /tmp/alpine.img   # This is a "sparse" file, not really 2G
# Start and login as "root" (no passwd)
./microvm.sh run_microvm /tmp/alpine.img
# (exit with ctrl-C)
./microvm.sh run_fc /tmp/alpine.img
# (exit with "kill 1")
```


## Networking

A `tun/tap` device is used since [firecracker only supports that](
https://github.com/firecracker-microvm/firecracker/blob/main/docs/network-setup.md).
The tap device (and an optional bridge) must be created before the vm
is started. Then the `--tap=` option can be specified to the run command.

```
sudo ./microvm.sh mktap --user=$USER --adr=172.20.0.1/24 tap0
./microvm.sh run_microvm --tap=tap0 /tmp/alpine.img
# Or:
./microvm.sh run_fc --tap=tap0 /tmp/alpine.img
# In the console
ip link    # You should see a "lo" and "eth0" interface (both DOWN)
```

This will *not* setup any networking in the guest. You can do that
manually.

```
# In the console:
ip link set up eth0
ip addr add 172.20.0.2/24 dev eth0
ping -c1 -W1 172.20.0.1     # Ping the host
```


## The rootfs

You can build you own customized root file system by setting the
`--rootfsar=` option and add "overlays", i.e. archives or directories
that will be copied to your root file system. The `rootfsar` must be
in `$HOME/Downloads` or `$ARCHIVE`.

```
./microvm.sh mkimage --rootfsar=alpine-minirootfs-3.18.0-x86_64.tar.gz /tmp/alpine.img ./templates/alpine
```

This takes an Alpine rootfs (unmodified) and add the files under
`./templates/alpine`.



## Minimum kernel config

This section describes how to build a minimum kernel that can be used
with `microvm`. Read also about the [Linux Kernel Tinification project](
https://tiny.wiki.kernel.org/start).

```
builddir=/tmp/$USER/minivm
mkdir -p $builddir
export __kcfg=$builddir/kernel.conf
export __kobj=$builddir/obj
export __kernel=$builddir/bzImage
./microvm.sh kernel_build --tinyconfig  # (will clear the config)
# just exit the kernel config and let it build
ls -lh $__kernel    # (491K at the time of writing)
```

You have now built an as small Linux kernel as possible. It is totally
useless, but may be interresting for minimalists (like myself).

The configuration described below is a minimum config to get a rootfs
and a serial console.

```
./microvm.sh kernel_build --menuconfig
# Enter:
[*] 64-bit kernel
[*] Enable the block layer
Executable file formats >
  [*] Kernel support for ELF binaries
  [*] Kernel support for scripts starting with #!
Device Drivers >
  Character devices >
    [*] Enable TTY
    [ ] (unmark Virtual terminal and others)
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

Unmark unnecessary things.


Test it:
```
ls -lh $__kernel    # (856K at the time of writing)
./microvm.sh run_microvm --mem=32 --init=/bin/sh /tmp/alpine.img
# (exit with ctrl-C)
./microvm.sh run_fc --mem=32 --init=/bin/sh /tmp/alpine.img
# (exit with "exit")
```

If you *really* want to learn about Linux kernel configuration, this
is a good place to start IMHO. Configure support for `procfs`,
`sysfs`, `kvmclock` and multi-user to start without
`--init=/bin/sh`. Take networking as an exercise.

```
General setup >
  Configure standard kernel features (expert users) >
    [*]   Multiple users, groups and capabilities support
    [*]   Enable support for printk
Processor type and features >
  [*] Linux guest support >
    [*]   Enable paravirtualization code
    [*]   KVM Guest support (including kvmclock)
File systems >
  Pseudo filesystems >
    [*] /proc file system support
    [*] sysfs file system support
```

