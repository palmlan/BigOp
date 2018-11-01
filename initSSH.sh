#!/bin/bash
# 
# 配置SSH密钥登录环境：启动ssh-agent，为用户添加可用的ssh钥匙，
# 然后复制本账号的ssh公钥到一批远程主机上, 完。
# Usage: 
#     initSSH.sh [hostsfile] [on] [password]
# Params:
#     hostsfile			A file containing ip addresse/FQDN/hostname of remote hosts.
#     on			Whether to keep ssh-agent running on.
#     password			remote login password
# 2018 lanyufeng

#verbose display
THIS_EXPAND=0
[[ ! $- =~ 'x' ]] || ( set -x && THIS_EXPAND=1 )

#初始化变量
HOSTSFILE=${1:-ip_hosts.txt}

if ! test -f "$HOSTSFILE" ; then
	echo "***Error: Hosts file not found: $HOSTSFILE"
	exit 1
fi

if ! which expect &>/dev/null; then
	echo '***command "expect" not found, it can be installed with: sudo apt-get install expect'
	echo "***Also ensure it's included in \$PATH"
	exit 1
fi

# main
echo "***远程主机ip地址列表：$HOSTSFILE"

if test -z "$LOGINPASSWD"; then
	echo "***为了建立SSH密钥登录，请输入本账号远程登录密码"
	echo "***（请确保与远程主机的账号密码一样）:"
	echo "***CAUTION: Password will be stored in shell variable insecurely, Use at your own risk!"
	read -s LOGINPASSWD
fi

# TBD:test if ssh-add can connect to existing ssh agent?
ssh-add -l &>/dev/null
case $? in
	2) # No, start a new ssh-agent
        	eval `ssh-agent -s` 
	;& #continue next command
	1)# yes, but no key has added
		ssh-add
	;;
esac
MY_AGENT_PID=$SSH_AGENT_PID

ex='^\s*#' # regex for comments in $HOSTSFILE
while read line; do
	#skip comments
	if [[ $line =~ $ex ]]; then continue; fi

	echo -e "\n[ssh-copy-id] Copying keyfile to remote host: $line"
expect <<EOF
	spawn ssh-copy-id -o StrictHostKeyChecking=no -i $line

	#REM repeat is an expect script variable
	set repeat 0

	expect {
		"s password:"	{
			if { \$repeat>0 } {
				send_user "\n***No! You typed a wrong login passwd just now! Quiting this script!\n"
				incr repeat
				#exit to eof now
				exit 		
			}
			send "$LOGINPASSWD\r"
			incr repeat
			exp_continue
		}
		eof		{ 
			if { \$repeat==2 } {
				exit 1
			}

			if { \$repeat==0 } {
				send_user "***Hey! Your key has already been authorized on $line!\n***You can ssh $line to login now!\n" 
			} 
		}
	}
EOF
	# Terminate script if longin passwd is wrong.
	[ ! $? ] && break
done < $HOSTSFILE

# If this script was called with 2nd parameter set to "on", then keep agent running on
# eg. source <this script> <param1> on
# otherwise quit the agent instance launched by this script, if there is one. 
# (eg. Agent not launched by this script will still be kept as is)
test "$2" = "on" || ( test -n "$MY_AGENT_PID" && ssh-agent -k )
test "$THIS_EXPAND" = "1" && set +x
