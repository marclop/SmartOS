#!/usr/bin/bash
#
# Bash script to restore all SmartOS VMs from Amazon S3
# This file will be executed manually due to the nature of the script, it will be usually used in DR scenarios or server replacement
# Author: Marc Lopez Rubio
# GitHub: https://github.com/marclop
# Mail: marc5.12@outlook.com
# Date: 17/07/2014

# Declaration of variables to be used
PATH="/usr/bin:/usr/sbin:/smartdc/bin:/opt/local/bin:/opt/local/sbin"
binname=$0
s3cfgurl=/opt/custom/s3cfgurl.txt
cfgurl=`cat $s3cfgurl`
restorepath=/opt/restore
s3bucket='s3://BUCKET'
StorageUsed=0

# Check if pip is installed, if not, install it
function checkpip {

	which pip >> /dev/null
	if [ $? -ne 0 ]; then

		pkgin in -y py27-pip
		echo "pip package installed"
	fi
}

# Installs the specified pip package and downloads the .s3cfg from the specified URL
function s3install {

	if [ $1 == s3cmd ]; then
		pkgin -y in py27-expat
		pip install $1
	fi
	curl -s -k -o $HOME/.s3cfg $cfgurl
}

# Download either all the VMs or a specific VM
function s3get {

	if [ ! -d $restorepath ]; then
		mkdir -p $restorepath
	fi

	# Check if specific VM has been specified
	if [ -z "$1" ] || [ $1 == "all" ];then

		# Because no VM has been specified, backup the last 5 VMs present in Amazon S3
		vmcount=`s3cmd ls $s3bucket | awk '{print $4}' | cut -d '/' -f4 | cut -d '-' -f1 | uniq | wc -l | awk '{print $1}'`
		s3contents=`s3cmd ls $s3bucket | sort | tail -$vmcount |awk '{print $4}'`
		check=0

		for i in $s3contents;do

			# Get the compressed VM from Amazon S3
			s3cmd get $i $restorepath

			# Get a clear VM name
			file=`echo $i | cut -d '/' -f4`

			# Test the integrity of the file
			lzma -t $restorepath/$file

			# Check the result from the file integrity check
			check=$?
			
			if [[ $check -ne 0 ]]; then
				break
			else
				continue
			fi
			
		done
			if [[ $check -ne 0 ]]; then
				return 1
			else
				return 0
			fi

	else

		# If no specific date has been specified, pick the last copy
		s3contents=`s3cmd ls $s3bucket | grep -i $1 | sort | tail -1 | awk '{print $4}'`

		# Get the compressed VM from Amazon S3
		s3cmd get $s3contents $restorepath

		# Test the integrity of the file
		file=`echo $s3contents | cut -d '/' -f4`
		
		# Test the integrity of the file
		lzma -t $restorepath/$file

		# Check the result from the file integrity check
		if [[ $? -ne 0 ]]; then
			return 1
		else
			return 0
		fi
		
	fi
}

# restore the VMs from the $restorepath to vmadm
function restore {

	# Get the item count in $restorepath
	items=`ls $restorepath | wc -l | awk '{print $1}'`

	# If $restorepath is empty exit with 1 
	if [[ $items -eq 0 ]]; then
		return 1
	fi

	# Check if specific VM has been specified
	if [ -z "$1" ] || [ $1 == "all" ];then

		restorecontents=`ls $restorepath`

		for i in $restorecontents;do
	
			# Decompress the VM and send it to vmadm
			lzma -d $restorepath/$i | vmadm receive
			if [[ $? -ne 0 ]]; then
				return 3
			else
				return 0
			fi
		done

	else

		restorecontents=`ls $restorepath/*$1*`

		# Checks if the VM exists if not, it will exit with the return code of 2
		if [[ ! -z $restorecontents ]]; then

			# Decompress the VM and send it to vmadm
			lzma -d $restorepath/$i | vmadm receive

			# Check the result from decompressing the VM and sending it to vmadm for VM import
			if [[ $? -ne 0 ]]; then
				return 3
			else
				return 0
			fi
		else
			return 2
		fi
	fi
}

# Start all the imported VMs through vmadm
function startvms {

	uniques=(`vmadm list | awk '{print $1}' | grep -v UUID`)

	for i in $uniques; do

		vmadm start $i

	done
}

# Cleanup function to remove everything in the $restorepath
function cleanup {

	items=`ls $restorepath | wc -l | awk '{print $1}'`

	if [[ $items -ne 0 ]]; then
		
		rm -f $restorepath/*

	else

		echo "Nothing to clean! $restorepath is empty!"

	fi
}

# Prints the script usage
function usage {

	echo
	echo "Usage: $binname [-h] [--help] [--usage] COMMAND [PARAMETER]"
	echo
	echo "COMMAND"
	echo
	echo -e "\\t fullrestore \\t \\t Make a full backup of all the VMs in the host to $backpath and transfer them to the specified Amazon S3 bucket ($s3bucket)"
	echo -e "\\t download \\t \\t Transfers all the local backups located in $backpath to the specified Amazon S3 bucket ($s3bucket)"
	echo -e "\\t restore \\t \\t Transfers all the local backups located in $backpath to the specified Amazon S3 bucket ($s3bucket)"
	echo -e "\\t list \\t \\t \\t Lists information about the Amazon S3 Bucket $s3bucket"
	echo -e "\\t clean \\t \\t \\t Deletes everything in the $restorepath folder"
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
	echo -e "Example: $binname fullrestore\\t Restore all VMs from the specified Amazon S3 bucket to the SmartOS host"
	echo -e "Example: $binname fullrestore all \\t Restore all VMs from the specified Amazon S3 bucket to the SmartOS host"
	echo -e "Example: $binname fullrestore mysql  Restore the VM aliased as mysql from the specified Amazon S3 bucket to the SmartOS host"
	echo -e "Example: $binname download all \\t download all VMs from the specified Amazon S3 bucket to the $restorepath"
	echo -e "Example: $binname download mysql \\t download the last VM Backup aliased as mysql from the specified Amazon S3 bucket to the $restorepath"
	echo -e "Example: $binname restore\\t Restores all VMs from $restorepath to the SmartOS host"
	echo -e "Example: $binname restore all \\t Restores all VMs from $restorepath to the SmartOS host"
	echo -e "Example: $binname restore mysql  Restores the mysql VM from $restorepath to the SmartOS host"
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
	echo -e "\\t restorepath \\t \\t $restorepath"
	echo -e "\\t s3cfgurl \\t \\t $s3cfgurl"
	echo -e "\\t cfgurl \\t \\t $cfgurl"
	echo -e "\\t s3bucket \\t \\t $s3bucket"
	echo -e "\\t uncheckedbacks \\t $uncheckedbacks"
	echo 
	exit 98
}

# Actual script execution
case $1 in
	config)
		config
		;;
	fullrestore)
		# Check if pip python package is installed and install it
		checkpip

		# Install s3cmd and set config for Amaris
		s3install s3cmd==1.5.0-alpha3

		# Get backup files
		s3get $2

		# Check the function return value
		case $? in
			1)
				echo "Integrity check failed, please download another backup";echo
				;;
			*)
			echo "Download completed!";echo
		esac

		# Restore backup
		restore $2

		# Check the function return value
		case $? in
			1)
				echo "$restorepath is EMPTY! Please downlaod the Backup before restoring it";echo
				;;
			2)
				echo "The specified VM $2 does not exist";echo
				;;
			3)
				echo "The backup decompression went wrong, please check vmadm logs";echo
				;;
			*)
			echo "Restore completed!";echo
		esac

		# Start the imported VMs
		startvms
		;;
	download)
		# Check if pip python package is installed and install it
		checkpip

		# Install s3cmd and set config for Amaris
		s3install s3cmd==1.5.0-alpha3

		# Get backup filess
		s3get $2

		# Check the function return value
		case $? in
			1)
				echo "Integrity check failed, please download another backup";echo
				;;
			*)
			echo "Download completed!";echo
		esac
		;;
	restore)
		# Check if pip python package is installed and install it
		checkpip

		# Install s3cmd and set config for Amaris
		s3install s3cmd==1.5.0-alpha3

		# Restore backup
		restore $2

		# Check restore function return value
		case $? in
			1)
				echo "$restorepath is EMPTY! Please downlaod the Backup before restoring it";echo
				;;
			2)
				echo "The specified VM $2 does not exist";echo
				;;
			3)
				echo "The backup decompression went wrong, please check vmadm logs";echo
				;;
			*)
			echo "Restore completed!";echo
		esac
		;;
	list)
		# Get the VMs in Amazon S3
		s3contents=`s3cmd ls $s3bucket | awk '{print $4}' | sort | cut -d '/' -f4`

		# Get the used storage in MB
		s3storage=`s3cmd ls $s3bucket -H| cut -d 'M' -f1 | awk '{print $3}'`

		# Count how many backups there are in Amazon S3
		backupcount=`s3cmd ls $s3bucket | wc -l | awk '{print $1}'`

		# Add all the storage to a single variable
		for i in $s3storage; do
			let "StorageUsed +=$i"
		done

		# Echo for prettyness
		echo; echo "Contents of $s3bucket:";echo

		# Convert MB to GB
		HumanStorage=`echo "scale=3;$StorageUsed /1024" | bc`

		# Print all VMs in list format
		for i in $s3contents; do
			echo -e "\\t $i"
		done;echo 

		echo "Nº of backups in $s3bucket: $backupcount"
		echo "Amount of storage used: $HumanStorage GB";echo
		;;
	clean)
		cleanup
		;;
	*)
	usage
esac
exit $?