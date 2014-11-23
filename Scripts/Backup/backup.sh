#!/usr/bin/bash
#
# Bash script to copy all SmartOS VMs, compress them and send them to Amazon S3
# This file will be placed in the SmartOS host and will be executed with the frequency specified to cron
# Author: Marc Lopez Rubio
# GitHub: https://github.com/marclop
# Mail: marc5.12@outlook.com
# Date: 16/07/2014

# Declaration of variables to be used
PATH="/usr/bin:/usr/sbin:/smartdc/bin:/opt/local/bin:/opt/local/sbin"
binname=$0
backpath=/opt/backup
date=`date +"%d%m%Y"`
exitcode=0
s3cfgurl=/opt/custom/s3cfgurl.txt
cfgurl=`cat $s3cfgurl`
s3bucket='s3://splbacks'
chunk=50
uncheckedbacks="/opt/uncheckedbacks"
HOME=/root

# Checks if the pip python package manager is installed
function checkpip {

	which pip >> /dev/null
	if [ $? -ne 0 ]; then

		pkgin in -y py27-pip
		echo "pip package installed"
	fi
}

# Install S3cmd with the pip python package manager
function s3install {

	if [ $1 == s3cmd ]; then
		pkgin -y in py27-expat
		pip install $1
	fi
	curl -s -k -o $HOME/.s3cfg $cfgurl
}

# Stops the running VMs, Compresses them and creates a .xz file and then starts the stopped VMs again
function backupvms {

	if [ -z "$1" ] || [ $1 == "all" ]; then

		# Get alias for each VM with vmadm command, for more information check vmadm
		aliases=(`vmadm list | awk '{print $5}' | grep -v ALIAS`)

		# Get the UUID for each VM with vmadm command, for more information check vmadm
		uniques=(`vmadm list | awk '{print $1}' | grep -v UUID`)

		# Get correct count parameter for the loop
		counts=0

		# Ensure that /opt/backup exists, if it doesn't create it
		if [ ! -d $backpath ]; then
			mkdir -p $backpath
		fi

		# for loop to process each VM
		for i in ${uniques[@]}
		do
			# Send the VM to LZMA (Compress using light compression)
			vmadm send $i | lzma -1 > $backpath/${aliases[$counts]}-$date.xz
			vmexit=$?
			if [ $vmexit -ne 0 ]; then
				exitcode=1
				echo "`date +%d-%m-%Y_%H:%M:%S`: Failed to compress ${aliases[$counts]}"
				echo "`date +%d-%m-%Y_%H:%M:%S`: The vmadm exit code is $vmexit"
				# In case the backup fails, start the VM automatically
				vmadm start $1
				echo "`date +%d-%m-%Y_%H:%M:%S`: Starting ${aliases{$counts]}"
				echo "`date +%d-%m-%Y_%H:%M:%S`: exitcode is $exitcode"
				exit $exitcode
			else
				echo "`date +%d-%m-%Y_%H:%M:%S`: Successfully backed up ${aliases[$counts]}"
			fi
			# Start the VM because vmadm send leaves it stopped :(
			vmadm start $i
			if [ $? -ne 0 ]; then
				exitcode=2
				echo "`date +%d-%m-%Y_%H:%M:%S`: Failed to start ${aliases[$counts]}"
				echo "`date +%d-%m-%Y_%H:%M:%S`: exitcode is $exitcode"
				exit $exitcode
			else
				echo "`date +%d-%m-%Y_%H:%M:%S`: Successfully started ${aliases[$counts]}"
			fi

			let "counts=counts+1"
		done

	else

		# Get alias for each VM with vmadm command, for more information check vmadm
		aliases=(`vmadm list | grep -i $1 | awk '{print $5}' | grep -v ALIAS`)

		# Get the UUID for each VM with vmadm command, for more information check vmadm
		uniques=(`vmadm list | grep -i $1 | awk '{print $1}' | grep -v UUID`)

		# Send the VM to LZMA (Compress using light compression)
		vmadm send $uniques | lzma -1 > $backpath/$aliases-$date.xz
		vmexit=$?
			if [ $vmexit -ne 0 ]; then
				exitcode=1
				echo "`date +%d-%m-%Y_%H:%M:%S`: Failed to compress ${aliases[$counts]}"
				echo "`date +%d-%m-%Y_%H:%M:%S`: The vmadm exit code is $vmexit"
				# In case the backup fails, start the VM automatically
				vmadm start $uniques
				echo "`date +%d-%m-%Y_%H:%M:%S`: Starting ${aliases{$counts]}"
				echo "`date +%d-%m-%Y_%H:%M:%S`: exitcode is $exitcode"
				exit $exitcode
		else
			echo "`date +%d-%m-%Y_%H:%M:%S`: Successfully backed up ${aliases[$counts]}"
		fi

		# Start the VM because vmadm send leaves it stopped :(
		vmadm start $uniques > /dev/null
		if [ $? -ne 0 ]; then
			exitcode=2
			echo "`date +%d-%m-%Y_%H:%M:%S`: Failed to start ${aliases[$counts]}"
			echo "`date +%d-%m-%Y_%H:%M:%S`: exitcode is $exitcode"
			exit $exitcode
		else
			echo "`date +%d-%m-%Y_%H:%M:%S`: Successfully started ${aliases[$counts]}"
		fi
	fi
}

# Function to transfer all VMs to Amazon S3
function s3transfer {

    # Check if no argument is passed (default)
	if [ -z "$1" ] || [ $1 == "all" ];then

		# Copy all VMs to the Amazon S3 Bucket
		vms=`ls $backpath`
		s3cmd --multipart-chunk-size-mb=$chunk put $backpath/* $s3bucket/
		echo "`date +%d-%m-%Y_%H:%M:%S`: Transfered all VMS to $s3bucket"
		
		# Necessary to recalculate the checksum, because the multipart upload generates a bad checksum that gives a WARNING when restoring the Backup
		for i in $vms; do
			s3cmd mv $s3bucket/$i $s3bucket/$i.
			s3cmd mv $s3bucket/$i. $s3bucket/$i

		done

	else
		# Copy the specified VM with the backup script to Amazon S3
		vm=`ls -l $backpath | awk '{print $9}' | grep -i $1`
		s3cmd --multipart-chunk-size-mb=$chunk put "$backpath/$vm" $s3bucket/
		s3cmd mv $s3bucket/$vm $s3bucket/$vm.
		s3cmd mv $s3bucket/$vm. $s3bucket/$vm
		echo "`date +%d-%m-%Y_%H:%M:%S`: Transfered $1 VM to $s3bucket"
	fi
}

# Contrasts the Local backups with the Amazon S3
function s3check {

    # Check if no argument is passed (default)
	if [ -z "$1" ] || [ $1 == "all" ];then

		# Contrast all VMs to the backups made to Amazon S3 Bucket

		contents=`ls $backpath/*.xz | cut -d '/' -f4 | sort`
		count=`vmadm list |grep -v ALIAS | wc -l | awk '{print $1}'`
        s3contents=`s3cmd ls $s3bucket | sort | tail -$count |awk '{print $4}' | cut -d '/' -f4 | sort`

        if [ ! "$contents" == "$s3contents" ]; then
                #exitcode=1
                #echo "`date +%d-%m-%Y_%H:%M:%S`: contents on Local storage and Amazon S3 do not match"
                #echo "exitcode is $exitcode"
                return 1
                #exit $exitcode
        else
                #echo "`date +%d-%m-%Y_%H:%M:%S`: contents on Local storage and Amazon S3 MATCH!"
                return 0
        fi

	else

		# Contrast the specified VM with the backup script to Amazon S3
		s3contents=`s3cmd ls $s3bucket | grep -i $1 |awk '{print $4}' | cut -d '/' -f4 | sort -r | tail -1`
		vm=`ls -l $backpath | awk '{print $9}' | grep -i $1`

		if [[ -z $vm ]] || [[ -z $s3contents ]]; then
			
			#echo "`date +%d-%m-%Y_%H:%M:%S`: contents on Local storage and Amazon S3 don't match"
			return 1
		fi

		if [ ! "$vm" == "$s3contents" ]; then
            #exitcode=1
            #echo "`date +%d-%m-%Y_%H:%M:%S`: contents on Local storage and Amazon S3 don't match"
            #echo "exitcode is $exitcode"
            return 1
            #exit $exitcode
        else
            #echo "`date +%d-%m-%Y_%H:%M:%S`: contents on Local storage and Amazon S3 MATCH!"
            return 0
        fi
		
	fi
}

# Removes local backup copy
function removeold {

	# If the Amazon S3 file matches the local one it will remove the local copy (no need to have duplicated files :) )
	# If the Amazon S3 file does not match the local one, it will move the local file to a safety folder before delete it because the contents do not match
	if s3check $1; then

		# Multiple files removal
		if [ -z "$1" ] || [ $1 == "all" ];then

			rm -f $backpath/*
			echo "`date +%d-%m-%Y_%H:%M:%S`: Erased $backpath/ contents"

		# Single file removal option
		else

			rm -f $backpath/$1
			echo "`date +%d-%m-%Y_%H:%M:%S`: Erased $backpath/$1 contents"

		fi

	else

		if [ ! -d $uncheckedbacks ];then

			mkdir -p $uncheckedbacks

		else

			# Moves multiple files to the unchecked backups folder
			if [ -z "$1" ] || [ $1 == "all" ];then
				
				mv $backpath/* $uncheckedbacks/.
				echo "`date +%d-%m-%Y_%H:%M:%S`: Moved $backpath/ contents to $uncheckedbacks"

			# Moves single file to the unchecked backups folder
			else

				mv $backpath/$1 $uncheckedbacks/.
				echo "`date +%d-%m-%Y_%H:%M:%S`: Moved $backpath/$1 to $uncheckedbacks/$1"

			fi

		fi

	fi
}

# Prints the script usage
function usage {

	echo;echo 'PLEASE BE CAREFULL WHEN USING THIS SCRIPT IT WILL STOP ALL RUNNING VMS!!!!!';echo
	echo "Usage: $binname [-h] [--help] [--usage] COMMAND [PARAMETER]"
	echo
	echo "COMMAND"
	echo
	echo -e "\\t fullbackup \\t \\t Make a full backup of all the VMs in the host to $backpath and transfer them to the specified Amazon S3 bucket ($s3bucket)"
	echo -e "\\t transfer \\t \\t Transfers all the local backups located in $backpath to the specified Amazon S3 bucket ($s3bucket)"
	echo -e "\\t check \\t \\t \\t Checks the last local backup made with the one located in the specified Amazon S3 bucket ($s3bucket)"
	echo -e "\\t rotate \\t \\t Checks the last local backup with Amazon S3 and removes the local backup"
	echo -e "\\t \\t \\t \\t NOTE: IF IT CANNOT CHECK THE LOCAL VMS WITH AMAZON IT WILL COPY THE FILES TO $uncheckedbacks"
	echo -e "\\t config \\t \\t Prints the current script config"
	echo -e "\\t help \\t \\t \\t Prints this help"
	echo
	echo "PARAMETER"
	echo
	echo -e "\\t all \\t \\t \\t does the specified command for all VMs"
	echo -e "\\t SPECIFIC_VM \\t \\t only applies the specified command to that SPECIFIC_VM"
	echo
	echo "EXAMPLES"
	echo 
	echo -e "Example: $binname fullbackup\\t \\t backup all VMs in the SmartOS host to the specified Amazon S3 bucket"
	echo -e "Example: $binname fullbackup all \\t backup all VMs in the SmartOS host to the specified Amazon S3 bucket"
	echo -e "Example: $binname fullbackup mysql \\t backup the VM aliased as mysql to the specified Amazon S3 bucket"
	echo -e "Example: $binname transfer all \\t transfer all VMs in the SmartOS $backpath to the specified Amazon S3 bucket"
	echo -e "Example: $binname transfer mysql \\t transfer the last VM Backup aliased as mysql in $backpath to the specified Amazon S3 bucket"
	echo -e "Example: $binname check all \\t \\t check all VMs in the SmartOS $backpath against the specified Amazon S3 bucket"
	echo -e "Example: $binname check mysql \\t check the last VM Backup aliased as mysql in $backpath against the specified Amazon S3 bucket"
	echo -e "Example: $binname rotate all \\t Rotate all VMs in the SmartOS $backpath against the specified Amazon S3 bucket and removes the local backup"
	echo -e "Example: $binname rotate mysql \\t Rotate the last VM Backup aliased as mysql in $backpath against the specified Amazon S3 bucket and removes the local backup"
	echo
	echo -e "Example: $binname -h \\t \\t show script usage"
	echo -e "Example: $binname --help \\t \\t show script usage"
	echo -e "Example: $binname --usage \\t \\t show script usage"
	echo
	exit 99
}

# Prints the current config
function config {
	echo
	echo "CONFIG VALUES"
	echo
	echo -e "\\t PATH \\t \\t \\t $PATH"
	echo -e "\\t backpath \\t \\t $backpath"
	echo -e "\\t date \\t \\t \\t $date"
	echo -e "\\t s3cfgurl \\t \\t $s3cfgurl"
	echo -e "\\t cfgurl \\t \\t $cfgurl"
	echo -e "\\t ChunkSize \\t \\t $chunk MB per chunk" 
	echo -e "\\t s3bucket \\t \\t $s3bucket"
	echo -e "\\t uncheckedbacks \\t $uncheckedbacks"
	echo 
	exit 98

}

# Script execution
case "$1" in
	config)
		config
		;;
	fullbackup)
		# Check if pip installed and s3cmd as well
		checkpip
		# Specify version because pip was installing s3cmd version 1.0.1 which doesn't support the multipart upload and causes files bigger than 5GB to fail
		s3install s3cmd==1.5.0-alpha3

		# Backup the VMs
		backupvms $2

		# Transfer the VMs
		s3transfer $2
		;;
	transfer)
		# Check if pip installed and s3cmd as well
		checkpip
		# Specify version because pip was installing s3cmd version 1.0.1 which doesn't support the multipart upload and causes files bigger than 5GB to fail
		s3install s3cmd==1.5.0-alpha3

		# Transfer VMs
		# If flag all specified, it will transfer all the VMs contained in the /opt/backup folder
		if [[ $2 == "all" ]]; then

					# Send the VMs to Amazon S3
					s3transfer
					exit $exitcode

		# IF ./backup transfer elk is called only the elk machine will be transfered being the latest copy
		else

			# Check if the VM exists in the local storage path and return the last copy made
			vm=`ls -lrt $backpath/*$2* | tail -1`

			# If the ls returns a value (meaning that the VM exists)
			if [[ ! -z $vm ]]; then

				# Transfer the actual VM
				s3transfer $2
				exit $exitcode

			# If the ls returns no value, exit the script
			else

				echo "No backup $2 available in $backpath"
				exit 100

			fi

		fi
		;;
	check)
		# Check if pip installed and s3cmd as well
		checkpip
		# Specify version because pip was installing s3cmd version 1.0.1 which doesn't support the multipart upload and causes files bigger than 5GB to fail
		s3install s3cmd==1.5.0-alpha3

		# Contrast local VMs with Amazon S3
		if [[ -z $2 ]]; then

			# Check Amazon S3 for the VMs
			s3check
			if [ $? -ne 0 ]; then

				exitcode=1
	            echo "`date +%d-%m-%Y_%H:%M:%S`: contents on Local storage and Amazon S3 don't match"
	            echo "exitcode is $exitcode"
	            exit $exitcode

        	else

	            echo "`date +%d-%m-%Y_%H:%M:%S`: contents on Local storage and Amazon S3 MATCH!"
	            echo "exitcode is $exitcode"
	            exit $exitcode

			fi
		else

			# Check Amazon S3 for the specified VM
			s3check $2
			if [ $? -ne 0 ]; then

				exitcode=1
	            echo "`date +%d-%m-%Y_%H:%M:%S`: contents on Local storage and Amazon S3 don't match"
	            echo "exitcode is $exitcode"
	            exit $exitcode

        	else

	            echo "`date +%d-%m-%Y_%H:%M:%S`: contents on Local storage and Amazon S3 MATCH!"
	            echo "exitcode is $exitcode"
	            exit $exitcode

			fi

		fi
		;;
	rotate)

			# Check Amazon S3 for the VMs
			# OR
			# Check Amazon S3 for the specified VM
			removeold $2
			exit $exitcode
			;;
	*)
	usage
esac
exit $exitcode