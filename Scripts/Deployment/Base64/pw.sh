#!/usr/bin/bash
#
#
#Password script to set the a random password to the desired user
#Author: Marc López Rubio
#Date 15/05/2014


export user=$1
export pass=` date +%s | sha256sum | base64 | head -c 32`

mdata-put $user\_pw $pass
sleep 1

expect<<EOF 
package require Expect

set user [lindex $argv 0]
#set password "Smartos2014"
set password [lindex $argv 1]

spawn passwd $user
expect "New Password:" { send "$password\r" }
expect "Re-enter new Password:" { send "$password\r" }
expect -exact "\r
passwd: password successfully changed for $user\r"
send -- ""
expect eof

EOF