#!/bin/bash
# 
# 初始化SSH免密登录环境：启动ssh-agent，添加ssh钥匙，
# 然后复制ssh公钥到一批远程主机上
# Usage: 
#     initSSH.sh [hostsfile] [on]
# Params:
#     hostfile			A file containing ip addresses of remote hosts.
#     on			Whether to keep ssh-agent running on.
# 2018 lanyufeng

#verbose display
THIS_EXPAND=0
[[ ! $- =~ 'x' ]] || ( set -x && THIS_EXPAND=1 )

#初始化变量

if test -f "$1" ; then
	HOSTSFILE=$1
else
	HOSTSFILE="ip_proxies.txt"
fi

if ! which expect &>/dev/null; then
	echo '***command "expect" not found, it can be installed with: sudo apt-get install expect'
	echo "***Also ensure it's included in \$PATH"
	exit 1
fi

# main
echo "***远程主机ip地址列表：$HOSTSFILE"
echo "***请输入本账号远程登录密码（请确保远程主机的账号密码都一样）:"
read -s LOGINPASSWD

# TBD:test if ssh-add can connect to existing ssh agent?
ssh-add -l &>/dev/null
case $? in
	2) # No, start a new ssh-agent
        	eval `ssh-agent -s` 
		MY_AGENT_PID=$SSH_AGENT_PID
	;& #continue next command
	1)# yes, but no key has added
		ssh-add
	;;
esac

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
# otherwise quit the agent instance launched by this script only, if there is any. 
# (eg. Agent not launched by this script will still be kept as is)
test "$2" = "on" || ( test -n "$MY_AGENT_PID" && ssh-agent -k )
test "$THIS_EXPAND" = "1" && set +x
