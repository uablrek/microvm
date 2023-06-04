# microvm

This repo covers two items:

* Create `microvm` images compatible with [firecracker](
  https://github.com/firecracker-microvm/firecracker) and
  [qemu-microvm](https://qemu.readthedocs.io/en/latest/system/i386/microvm.html)

* Use microvms in [Kubernetes](https://kubernetes.io/) using
  [kata-containers](https://github.com/kata-containers/kata-containers)


The original goal was to run `kata-containers` with `firecracker` in
[KinD](https://kind.sigs.k8s.io/), but then you must be able to create
compatible vm-images.


## Setup and the microvm.sh script

Most things are done using the `microvm.sh` script.
```
./microvm.sh        # Help printout
./microvm.sh env    # Print current environment
./microvm.sh setup  # Install items in $MICROVM_WORKSPACE
```


## Test a kernel and rootfs

To be useful as a `kata-container` the image must have a rootfs with a
kernel and a boot-loader. However, for learning and test with
`firecracker` and `qemu-microvm` we can use a rootfs without kernel
and specify the kernel on start.