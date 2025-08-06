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
findar() {
	findf $1.tar.bz2 || findf $1.tar.gz || findf $1.tar.xz || findf $1.tgz || findf $1.zip
}
# Set variables unless already defined
eset() {
	local e k
	for e in $@; do
		k=$(echo $e | cut -d= -f1)
		opts="$opts|$k"
		test -n "$(eval echo \$$k)" || eval $e
		test "$(eval echo \$$k)" = "?" && eval $e
	done
}

##   env
##     Print environment
cmd_env() {
	test "$envread" = "yes" && return 0
	envread=yes

	eset \
		MICROVM_WORKSPACE=/tmp/tmp/$USER/microvm \
		ARCHIVE=$HOME/archive \
		ver_kernel=linux-6.16 \
		ver_fc=firecracker-v1.12.1-x86_64 \
		ver_alpine=alpine-minirootfs-3.22.1-x86_64 \
		ver_diskim=diskim-1.1.0
	WS=$MICROVM_WORKSPACE
	__kdir=$WS/$ver_kernel			# (hard-code this for now)
	eset \
		ARCHIVE=$HOME/Downloads \
		__kdir=$WS/$ver_kernel \
		__kcfg=$dir/config/$ver_kernel \
		__kobj=$WS/obj/$ver_kernel \
		__fccfg=$dir/config/vm_config.json \
		__image=$WS/rootfs.img
	eset __kernel=$__kobj/arch/x86/boot/bzImage
	if test "$cmd" = "env"; then
		set | grep -E "^($opts)="
		exit 0
	fi

	mkdir -p "$WS"
	cd $dir
}
##   setup [--clean]
##     The $MICROVM_WORKSPACE dir is used which defaults to
##     $HOME/tmp/microvm. This should be executed when diskim or the kernel
##     is updated, or on initial setup
cmd_setup() {
	if test "$__clean" = "yes"; then
		rm -rf $WS
		mkdir -p $WS
	fi

	local installed
	if ! test -x "$diskim"; then
		findar $ver_diskim || die "Not found [$ver_diskim]"
		tar -C $WS -xf $f || die "tar -xf $f"
		installed=$ver_diskim
	fi

	if ! test -d $__kdir; then
		findar $ver_kernel || die "Not found [$ver_kernel]"
		xz -d -c -T0 $f | tar -C $WS -x || die "Unpack [$f]"
		installed="$installed $ver_kernel"
	fi

	if ! test -d $WS/$ver_fc; then
		findar $ver_fc || die "Not found [$ver_fc]"
		tar -C $WS -xf $f || die "tar -xf $f"
		# The fc dir is named "release-*" for some reason
		local silly_name=$(echo $ver_fc | sed -e 's,firecracker-,release-,')
		mv $WS/$silly_name $WS/$ver_fc
		installed="$installed $ver_fc"
	fi

	findar $ver_alpine || log "WARNING: Not found [$ver_alpine]"
	if test -n "$installed"; then
		log "Installed: $installed"
	else
		log "Everything setup already"
	fi
}
##   kernel_build [--menuconfig] [--tinyconfig]
##     Build the microvm kernel
cmd_kernel_build() {
	if test "$__tinyconfig" = "yes"; then
		rm -r $__kobj
		mkdir -p $__kobj $(dirname $__kcfg)
		make -C $__kdir O=$__kobj tinyconfig
		cp $__kobj/.config $__kcfg
		__menuconfig=yes
	fi
	test -r $__kcfg || die "Not readable [$__kcfg]"
	mkdir -p $__kobj
	cp $__kcfg $__kobj/.config
	if test "$__menuconfig" = "yes"; then
		make -C $__kdir O=$__kobj menuconfig || die menuconfig
		cp $__kobj/.config $__kcfg
	fi
	make -j$(nproc) -C $__kdir O=$__kobj
}
##   mkimage [--image=] [--size=2G] [--rootfsar=] [ovls...]
##     Create a disk image from a rootfs archive and optional overlays
cmd_mkimage() {
	if test -n "$__rootfsar"; then
		test -r "$__rootfsar" || die "Not readable [$__rootfsar]"
		f=$__rootfsar
	else
		findar $ver_alpine || die "Not found [$ver_alpine]"
	fi
	eset __size=2G
	unset __kernel
	export __image
	local d=$WS/$ver_diskim
	export DISKIM_WORKSPACE=$d/tmp # (due to a bug in diskim)
	$d/diskim.sh mkimage --size=$__size --format=raw $f $@ || die diskim
}
##   mktap [--bridge=|--adr=] <tap>
##     Create a network tun/tap device.  The tun/tap device can
##     optionally be attached to a bridge.
##     Requires "sudo"!
cmd_mktap() {
	test -n "$1" || die "Parameter missing"
	if ip link show dev $1 > /dev/null 2>&1; then
		log "Device exists [$1]"
		return 0
	fi
	if test -n "$__bridge"; then
		ip link show dev $__bridge > /dev/null 2>&1 \
			|| die "Bridge does not exist [$__bridge]"
	fi
	sudo ip tuntap add $1 mode tap user $USER || die "Create tap"
	sudo ip link set up $1
	if test -n "$__bridge"; then
		sudo ip link set dev $1 master $__bridge || die "Attach to bridge"
	elif test -n "$__adr"; then
		local opt
		echo "$__adr" | grep -q : && opt=-6
		sudo ip $opt addr add $__adr dev $1 || die "Set address [$__adr]"
	fi
}
##   run_microvm [--init=/init] [--mem=128] [--tap=] [--image=]
##     Run a qemu microvm
cmd_run_microvm() {
	eset __init=/init __mem=128
	local opt="-smp 2 -k sv -m $__mem"
    opt="$opt -drive file=$__image,if=none,id=drive0,format=raw"
    opt="$opt -device virtio-blk-device,drive=drive0"
	if test -n "$__tap"; then
		setmac
		opt="$opt -netdev tap,id=$__tap,script=no,ifname=$__tap"
		opt="$opt -device virtio-net-device,netdev=$__tap,mac=$mac"
	fi
    exec qemu-system-x86_64-microvm -enable-kvm \
		-M microvm,acpi=off,x-option-roms=off,pit=on,pic=off,rtc=off \
		-cpu host -nodefaults -no-user-config -nographic -no-reboot \
        -serial stdio -kernel $__kernel $opt \
        -append "console=ttyS0 root=/dev/vda init=$__init rw reboot=t $@"
}
setmac() {
	local b0=$(echo $__tap | tr -dc '[0-9]')
	if test -n "$b0"; then
		b0=$(printf "%02d" $b0)
	else
		b0=00
	fi
	mac=00:00:00:01:00:$b0
}
##   run_fc [--init=/init] [--mem=128] [--tap=] [--image=]
##     Run a firecracker vm
cmd_run_fc() {
	local fc=$WS/$ver_fc/$ver_fc
	test -x $fc || die "Not executable [$fc]"
	eset __init=/init __mem=128
	mkdir -p $tmp
	local kernel=$__kobj/vmlinux
	sed -e "s,vmlinux.bin,$kernel," -e "s,bionic.rootfs.ext4,$__image," \
		-e "s,/init,$__init," \
		-e "s,\"mem_size_mib\": 1024,\"mem_size_mib\": $__mem," \
		< $__fccfg > $tmp/fc-config.json
	if test -n "$__tap"; then
		setmac
		cat > $tmp/addnet <<EOF
."network-interfaces" += [{
  "iface_id": "eth0",
  "guest_mac": "$mac",
  "host_dev_name": "$__tap"
}]
EOF
		jq -f $tmp/addnet $tmp/fc-config.json > $tmp/fc-config-net.json
		mv -f $tmp/fc-config-net.json $tmp/fc-config.json
	fi
	$fc --no-api --config-file $tmp/fc-config.json
}


##
# Get the command
cmd=$(echo $1 | tr -- - _)
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
cmd_env
cmd_$cmd "$@"
status=$?
rm -rf $tmp
exit $status
