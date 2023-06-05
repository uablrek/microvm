#! /bin/sh
##
## microvm.sh --
##
##   Help script for https://github.com/uablrek/microvm
##
## Commands;
##

prg=$(basename $0)
dir=$(dirname $0); dir=$(readlink -f $dir)
tmp=/tmp/${prg}_$$

die() {
    echo "ERROR: $*" >&2
    rm -rf $tmp
    exit 1
}
help() {
    grep '^##' $0 | cut -c3-
    rm -rf $tmp
    exit 0
}
test -n "$1" || help
echo "$1" | grep -qi "^help\|-h" && help

log() {
	echo "$*" >&2
}
findf() {
	f=$ARCHIVE/$1
	test -r $f && return 0
	f=$HOME/Downloads/$1
	test -r $f
}

##   env
##     Print environment.
cmd_env() {
	test "$envread" = "yes" && return 0
	envread=yes

	test -n "$MICROVM_WORKSPACE" || export MICROVM_WORKSPACE=$HOME/tmp/microvm
	test -d "$MICROVM_WORKSPACE" || mkdir -p "$MICROVM_WORKSPACE"
	test -n "$ARCHIVE" || export ARCHIVE=$HOME/Downloads
	test -n "$__ksetup" || __ksetup=default
	test -n "$__kver" || __kver=linux-6.3.4
    test -n "$__kdir" || __kdir=$MICROVM_WORKSPACE/$__kver
	test -n "$__kcfg" || __kcfg=$dir/config/$__kver/$__ksetup
	test -n "$__kernel" || __kernel=$MICROVM_WORKSPACE/bzImage-$__kver-$__ksetup
	test -n "$__kobj" || __kobj=$MICROVM_WORKSPACE/obj-$__kver-$__ksetup
	test -n "$__fcver" || __fcver=v1.3.1
	fc=$MICROVM_WORKSPACE/release-$__fcver-x86_64/firecracker-$__fcver-x86_64
	if test -z "$DISKIM"; then
		DISKIM=$(find $MICROVM_WORKSPACE -name diskim.sh)
		test -n "$DISKIM" || log "WARNING: diskim not installed"
	fi

	if test "$cmd" = "env"; then
		local opts="kver|kcfg|kobj|kdir|fcver|kernel"
		set | grep -E "^(__($opts)|MICROVM_.*|ARCHIVE|DISKIM|fc)=" | sort
		return 0
	fi
}
##   setup
##     The $MICROVM_WORKSPACE dir is used which defaults to
##     $HOME/tmp/microvm. This should be executed when diskim or the kernel
##     is updated, or on initial setup
cmd_setup() {
	cmd_env
	if test -n "$DISKIM"; then
		log "Already installed [$DISKIM]"
	else
		local diskim_ver=1.0.0
		log "Installing diskim $diskim_ver ..."
		local ar=diskim-$diskim_ver.tar.xz
		if ! findf $ar; then
			curl -L -o $ARCHIVE/$ar https://github.com/lgekman/diskim/releases/download/$diskim_ver/$ar || die "FAILED: Download diskim"
			findf $ar || die "FAILED: diskim not found"
		fi
		tar -C $MICROVM_WORKSPACE -xf $f || die "FAILED: tar -xf $f"
		DISKIM=$(find $MICROVM_WORKSPACE -name diskim.sh)
		test -x $DISKIM || die "Not executable [$DISKIM]"
	fi

	if test -d $__kdir; then
		log "Already installed [$__kdir]"
	else
		export __kver __kdir
		$DISKIM kernel_download || die "FAILED"
		$DISKIM kernel_unpack  || die "FAILED"
	fi

	if test -x $fc; then
		log "Already installed [$fc]"
	else
		local ar=firecracker-$__fcver-x86_64.tgz
		log "Installing $ar ..."
		if ! findf $ar; then
			curl -L -o $ARCHIVE/$ar https://github.com/firecracker-microvm/firecracker/releases/download/$__fcver/$ar || die "FAILED: Download firecracker"
			findf $ar || die "FAILED: firecracker not found"
		fi
		tar -C $MICROVM_WORKSPACE -xf $f || die "FAILED: tar -xf $f"
		test -x $fc || die "FAILED: Install firecracker"
	fi
}
##   docker_export <image>
##     Like "docker export" but for an image
cmd_docker_export() {
	test -n "$1" || die "Parameter missing"
	docker image inspect $1 > /dev/null || die FAILED
    local c=$(docker create $1 sh) || die "FAILED; docker create"
    docker export $c
    docker rm $c > /dev/null 2>&1
}
##   kernel_build [--menuconfig]
##     Build the microvm kernel
cmd_kernel_build() {
	cmd_env
	export __kver __kdir __kcfg __kobj __kernel
	$DISKIM kernel_build --menuconfig=$__menuconfig
}
##   mkimage [--size=2G] --docker-image=image <output-file>
##     Create a disk image from a docker image
cmd_mkimage() {
	cmd_env
	test -n "$1" || die "Parameter missing"
	test -n "$__docker_image" || die "Missing --docker-image"
	mkdir -p $tmp
	cmd_docker_export $__docker_image > $tmp/image.tar
	$DISKIM mkimage --size=$__size --format=raw --image=$1 $tmp/image.tar || die FAILED
}
##   run_microvm [--init=/init] [--mem=128] <image>
##     Run a qemu microvm
cmd_run_microvm() {
	cmd_env
	test -n "$1" || die "Parameter missing"
	test -r "$1" || die "Not readable [$1]"
	local image=$1
	shift
	test -n "$__init" || __init=/init
	test -n "$__mem" || __mem=128
	local kvmboot="-smp 2 -k sv -m $__mem"
    kvmboot="$kvmboot -drive file=$image,if=none,id=drive0,format=raw"
    kvmboot="$kvmboot -device virtio-blk-device,drive=drive0"
    exec qemu-system-x86_64-microvm -enable-kvm -M microvm,acpi=off \
		-cpu host -nodefaults -no-user-config \
        -serial stdio -kernel $__kernel $kvmboot \
        -append "console=ttyS0 root=/dev/vda init=$__init rw $__append"
}
##   run_fc [--init=/init] [--mem=128] <image>
##     Run a firecracker vm
cmd_run_fc() {
	cmd_env
	test -n "$1" || die "Parameter missing"
	test -r "$1" || die "Not readable [$1]"
	local image=$1
	test -n "$__init" || __init=/init
	test -n "$__mem" || __mem=128
	mkdir -p $tmp
	local kernel=$__kobj/vmlinux
	sed -e "s,vmlinux.bin,$kernel," -e "s,bionic.rootfs.ext4,$image," \
		-e "s,/init,$__init," \
		-e "s,\"mem_size_mib\": 1024,\"mem_size_mib\": $__mem," \
		< $dir/config/vm_config.json > $tmp/fc-config.json
	$fc --no-api --config-file $tmp/fc-config.json
}


##
# Get the command
cmd=$1
shift
grep -q "^cmd_$cmd()" $0 $hook || die "Invalid command [$cmd]"

while echo "$1" | grep -q '^--'; do
	if echo $1 | grep -q =; then
		o=$(echo "$1" | cut -d= -f1 | sed -e 's,-,_,g')
		v=$(echo "$1" | cut -d= -f2-)
		eval "$o=\"$v\""
	else
		if test "$1" = "--"; then
			shift
			break
		fi
		o=$(echo "$1" | sed -e 's,-,_,g')
		eval "$o=yes"
	fi
	shift
done
unset o v
long_opts=`set | grep '^__' | cut -d= -f1`

# Execute command
trap "die Interrupted" INT TERM
cmd_$cmd "$@"
status=$?
rm -rf $tmp
exit $status
