#!/opt/local/bin/expect
#
#Author: Marc López Rubio
#Date 15/05/2014
#Modified 20/05/2014

#Password script to set the a random password to the desired user
#Expects you to send the USERNAME as the 1st argument and the password as the second one

package require Expect

#Variable declaration
set user [lindex $argv 0]
set password [lindex $argv 1]

#Actual script code
spawn passwd $user
expect "New Password:" { send "$password\r" }
expect "Re-enter new Password:" { send "$password\r" }
expect -exact "\r
passwd: password successfully changed for $user\r"
send -- ""
expect eof