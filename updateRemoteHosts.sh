#!/bin/bash
# 远程执行版本更新操作，不支持打补丁，通过ssh复制、更新部分现网文件，如果
# 新文件是tar文件，则会提示是否在目标文件夹中解开tar。更新前会提示用户是否
# 备份源文件到一个tar文件中。

# Usage:
#    updateRemoteHosts.sh [hostsfile]
# Params:
#     hostfile                  A file containing ip addresses of remote hosts.
#				default is ip_hosts.txt
# 2018 lanyufeng

# Start of config variables
# 初始化变量
set -x; set -u
UpdateFrom=(../../UpdateProxy/sbin/proxy.jar ../../UpdateProxy/tools/minicap/shared/android-28)
echo "***源文件或文件夹包括 ${UpdateFrom[*]}"
UpdateTo=(/opt/aspire/product/iproxy/proxy/sbin /opt/aspire/product/iproxy/proxy/tools/minicap/shared/)
echo "***目标文件夹包括 ${UpdateTo[*]}"
if [[ ${#UpdateFrom[*]} -ne ${#UpdateTo[*]} ]]; then
	echo "***ERR: 请重新检查，源文件或文件夹必须指定对应的目标文件夹!"
	exit 1
fi 

SERVICE=proxyd
echo "***更新前后需要重启的服务是：$SERVICE"

if [[ $# > 0 && -f "$1" ]]; then
        HOSTSFILE=$1
else
        HOSTSFILE="ip_hosts.txt"
fi
echo "***远程主机ip地址列表：$HOSTSFILE"

# End of config variables

UNTAR_CMD="tar -xv --no-overwrite-dir -f"
TAR_CMD="tar -uvPf"

do_backup () {
	test -n "$1" || return 1
	local bakfilename=$1
	local reg1='/$'
	# remove trailing slash
	while [[ "$bakfilename" =~ $reg1 ]]; do
		bakfilename=${bakfilename%/}
	done
	bakfilename=${bakfilename:-rootdir}_$(date +%F).tar

	echo "***Backup files in 目标文件夹 $1 for all remote hosts into $bakfilename"
	echo "***WARNING: ANY FILE WITH THE SAME NAME WILL BE REPLACED!"
	read -n 1 -p "Choose (y)Continue backup; (S)Skip backup and begin update: (Any other key will quit immediately.)" ANSWER
	case  "$ANSWER" in
		'S')	return 0 ;;
		'y')	pssh -ih $HOSTSFILE $TAR_CMD $bakfilename $1 ;;
		*)	do_exit 0 ;;
	esac
}

do_exit () {
	echo "***Exiting"
local RETVAL
	if test -n "$1" ; then
		RETVAL=$1
	else 
		RETVAL=0
	fi
	# Quit the agent instance launched by this script only if there is any. 
	# (eg. Agent not launched by this script will be kept as is)
	test -n "$MY_AGENT_PID" && ssh-agent -k
	set +x; set +u
	exit $RETVAL
}	

do_update () {
	sudo sudo service $SERVICE stop || do_exit $?

	pscp -h $HOSTSFILE -o . -e . -r $1  $2

	local regex='\.tar$'
	if [[ $1 =~ $regex ]]; then
		TARFILE=${1##*/}
		#Ask user how to deal with tar
		while true; do
			read -n 1 -p "是否在目标文件夹$2中打开${TARFILE}？List the tar content/Yes/No(type L/Y/N):" ANSWER
			case "$ANSWER" in 
				"L")
					tar -tvf $1
					continue
					;;	
				"y")	# the magic shell parameter expansion used here to trim preceding path names
					pssh -ih $HOSTSFILE $UNTAR_CMD ${2}/$TARFILE  || do_exit $?
					;;
				"n")
					break
					;;
				*)
					echo "Please type L, y or n only!"
					;;
			esac
		done
	fi

	sudo service $SERVICE start || do_exit $?
}
	
# 初始化检查
echo "***检查所需软件: pssh"
if ! ( which pssh &>/dev/null ); then
	if ( which virtualenv &>/dev/null );  then
		echo "***Fatal: Python pssh module is not available, please check your"
		echo "***virtualenv configuration and switch to the correct project."
		exit 1
	fi
	echo "***Fatal: Python pssh module not found in \$PATH"
	echo "***sudo pip install pssh' ( or setup a special \"virtualenv\" project. )"
	exit 1
fi

which pscp &>/dev/null || do_exit $?

# test if ssh-add can connect to existing ssh agent if there is any?
ssh-add -l &>/dev/null
if [[ "$?" = 2 ]]; then
        # No, start a new ssh-agent
        eval `ssh-agent -s` 
	MY_AGENT_PID=$SSH_AGENT_PID 
fi
ssh-add

echo "***Setup key authentication with remote hosts."
test -x ./initSSH.sh && source ./initSSH.sh $HOSTSFILE on


# main
i=0 
BATCHDO=0

for src in ${UpdateFrom[*]}; do
	if ! test -r "$src"; then
		echo "File not found: $src"
		do_exit 1
	fi

	test -n "${UpdateTo[$i]}" || do_exit 1
	dest=${UpdateTo[$i]}

	i=$((i+1))

	do_backup $dest || do_exit $?
	echo "***Copy $src to $dest on remote hosts"
	
	if [ "$BATCHDO" = 1 ]; then
		do_update $src $dest
	else
		read -n 1 -p "Continue? Yes(Y)/Yes to all(A)/No(N)/Skip(S):" ANSWER
		case $ANSWER in
			'A')	
				BATCHDO=1
				;&
			'Y')
				do_update $src $dest
				;;
			'S')
				continue
				;;
			'N')
				do_exit 0
				;;
		esac
	fi

done

do_exit 0
