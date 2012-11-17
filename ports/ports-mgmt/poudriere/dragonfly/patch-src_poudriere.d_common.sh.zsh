--- /dev/null	2012-11-17 15:39:32.218135384 +0100
+++ src/poudriere.d/common.sh.zfs	2012-11-17 16:14:45.000000000 +0100
@@ -0,0 +1,187 @@
+#!/bin/sh
+
+# zfs namespace
+NS="poudriere"
+
+zget() {
+	[ $# -ne 1 ] && eargs property
+	zfs get -H -o value ${NS}:${1} ${JAILFS}
+}
+
+zset() {
+	[ $# -ne 2 ] && eargs property value
+	zfs set ${NS}:$1="$2" ${JAILFS}
+}
+
+pzset() {
+	[ $# -ne 2 ] && eargs property value
+	zfs set ${NS}:$1="$2" ${PTFS}
+}
+
+pzget() {
+	[ $# -ne 1 ] && eargs property
+	zfs get -H -o value ${NS}:${1} ${PTFS}
+}
+
+zsnap() {
+	[ $# -ne 1 ] && eargs filesystem@snapname
+	zfs snapshot ${1}
+}
+
+zkill() {
+	[ $# -ne 1 ] && eargs filesystem@snapname
+	zfs destroy -r ${1}
+}
+
+zrollback () {
+	[ $# -ne 1 ] && eargs filesystem@snapname
+	zfs rollback -R ${1}
+}
+
+zdiff () {
+	[ $# -ne 2 ] && eargs filesystem@snapname filesystem
+	zfs diff -FH ${1} ${2}
+}
+
+jail_exists() {
+	[ $# -ne 1 ] && eargs jailname
+	zfs list -rt filesystem -H -o ${NS}:type,${NS}:name ${ZPOOL}${ZROOTFS} | \
+		awk -v n=$1 'BEGIN { ret = 1 } $1 == "rootfs" && $2 == n { ret = 0; } END { exit ret }' && return 0
+	return 1
+}
+
+jail_get_base() {
+	[ $# -ne 1 ] && eargs jailname
+	zfs list -rt filesystem -s name -H -o ${NS}:type,${NS}:name,mountpoint ${ZPOOL}${ZROOTFS} | \
+		awk -v n=$1 '$1 == "rootfs" && $2 == n  { print $3 }' | head -n 1
+}
+
+jail_get_version() {
+	[ $# -ne 1 ] && eargs jailname
+	zfs list -rt filesystem -s name -H -o ${NS}:type,${NS}:name,${NS}:version ${ZPOOL}${ZROOTFS} | \
+		awk -v n=$1 '$1 == "rootfs" && $2 == n { print $3 }' | head -n 1
+}
+
+jail_get_fs() {
+	[ $# -ne 1 ] && eargs jailname
+	zfs list -rt filesystem -s name -H -o ${NS}:type,${NS}:name,name ${ZPOOL}${ZROOTFS} | \
+		awk -v n=$1 '$1 == "rootfs" && $2 == n { print $3 }' | head -n 1
+}
+
+port_exists() {
+	[ $# -ne 1 ] && eargs portstree_name
+	zfs list -t filesystem -H -o ${NS}:type,${NS}:name,name | \
+		awk -v n=$1 'BEGIN { ret = 1 } $1 == "ports" && $2 == n { ret = 0; } END { exit ret }' && return 0
+	return 1
+}
+
+port_get_base() {
+	[ $# -ne 1 ] && eargs portstree_name
+	zfs list -t filesystem -H -o ${NS}:type,${NS}:name,mountpoint | \
+		awk -v n=$1 '$1 == "ports" && $2 == n { print $3 }'
+}
+
+port_get_fs() {
+	[ $# -ne 1 ] && eargs portstree_name
+	zfs list -t filesystem -H -o ${NS}:type,${NS}:name,name | \
+		awk -v n=$1 '$1 == "ports" && $2 == n { print $3 }'
+}
+
+get_data_dir() {
+	local data
+	if [ -n "${POUDRIERE_DATA}" ]; then
+		echo ${POUDRIERE_DATA}
+		return
+	fi
+	data=$(zfs list -rt filesystem -H -o ${NS}:type,mountpoint ${ZPOOL}${ZROOTFS} | awk '$1 == "data" { print $2 }' | head -n 1)
+	if [ -n "${data}" ]; then
+		echo $data
+		return
+	fi
+	zfs create -p -o ${NS}:type=data \
+		-o mountpoint=${BASEFS}/data \
+		${ZPOOL}${ZROOTFS}/data
+	echo "${BASEFS}/data"
+}
+
+jail_create_zfs() {
+	[ $# -ne 5 ] && eargs name version arch mountpoint fs
+	local name=$1
+	local version=$2
+	local arch=$3
+	local mnt=$( echo $4 | sed -e "s,//,/,g")
+	local fs=$5
+	msg_n "Creating ${name} fs..."
+	zfs create -p \
+		-o ${NS}:type=rootfs \
+		-o ${NS}:name=${name} \
+		-o ${NS}:version=${version} \
+		-o ${NS}:arch=${arch} \
+		-o mountpoint=${mnt} ${fs} || err 1 " Fail" && echo " done"
+}
+
+port_create_zfs() {
+	[ $# -ne 3 ] && eargs name mountpoint fs
+	local name=$1
+	local mnt=$( echo $2 | sed -e 's,//,/,g')
+	local fs=$3
+	msg_n "Creating ${name} fs..."
+	zfs create -p \
+		-o mountpoint=${mnt} \
+		-o ${NS}:type=ports \
+		-o ${NS}:name=${name} \
+		${fs} || err 1 " Fail" && echo " done"
+}
+
+start_builders() {
+	local arch=$(zget arch)
+	local version=$(zget version)
+	local j mnt fs name
+
+	zfs create -o canmount=off ${JAILFS}/build
+
+	for j in ${JOBS}; do
+		mnt="${JAILMNT}/build/${j}"
+		fs="${JAILFS}/build/${j}"
+		name="${JAILNAME}-job-${j}"
+		zset status "starting_jobs:${j}"
+		mkdir -p "${mnt}"
+		zfs clone -o mountpoint=${mnt} \
+			-o ${NS}:name=${name} \
+			-o ${NS}:type=rootfs \
+			-o ${NS}:arch=${arch} \
+			-o ${NS}:version=${version} \
+			${JAILFS}@prepkg ${fs}
+		zsnap ${fs}@prepkg
+		# Jail might be lingering from previous build. Already recursively
+		# destroyed all the builder datasets, so just try stopping the jail
+		# and ignore any errors
+		jail -r ${name} >/dev/null 2>&1 || :
+		MASTERMNT=${JAILMNT} JAILNAME=${name} JAILMNT=${mnt} JAILFS=${fs} do_jail_mounts 0
+		MASTERMNT=${JAILMNT} JAILNAME=${name} JAILMNT=${mnt} JAILFS=${fs} do_portbuild_mounts 0
+		MASTERMNT=${JAILMNT} JAILNAME=${name} JAILMNT=${mnt} JAILFS=${fs} jrun 0
+		JAILFS=${fs} zset status "idle:"
+	done
+}
+
+stop_builders() {
+	local j mnt
+
+	# wait for the last running processes
+	cat ${JAILMNT}/poudriere/var/run/*.pid 2>/dev/null | xargs pwait 2>/dev/null
+
+	msg "Stopping ${PARALLEL_JOBS} builders"
+
+	for j in ${JOBS}; do
+		jail -r ${JAILNAME}-job-${j} >/dev/null 2>&1 || :
+	done
+
+	mnt=`realpath ${JAILMNT}`
+	mount | awk -v mnt="${mnt}/build/" 'BEGIN{ gsub(/\//, "\\\/", mnt); } { if ($3 ~ mnt && $1 !~ /\/dev\/md/ ) { print $3 }}' |  sort -r | xargs umount -f 2>/dev/null || :
+
+	zkill ${JAILFS}/build 2>/dev/null || :
+
+	# No builders running, unset JOBS
+	JOBS=""
+}
+
