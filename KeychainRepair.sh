#!/bin/bash
#####################################
#
# Keychain Repair
#
# Removes a User's login keychain, creates a new login keychain, sets it
# as the default keychain, deletes any Local Items keychain folders,
# then reboots the system interactively
#
# University of North Carolina Asheville ITS
#      contact <bmwarren@unca.edu>
#      author: Matthew Warren
#      created: 2014-09-06
#      modified: 2017-08-21 (Total Eclipse of the Heart Edition)
#
#####################################

# Location of cocoaDialog binary
ccd="/Applications/cocoaDialog.app/Contents/MacOS/cocoaDialog"

# JSS trigger to install cocoaDialog if not found
ccd_trigger="installcocoadialog"

# Quit apps command
read -r -d '' OSASCRIPT_COMMAND <<EOD
set white_list to {"Finder","Self Service"}
tell application "Finder"
	set process_list to the name of every process whose visible is true
end tell
repeat with i from 1 to (number of items in process_list)
	set this_process to item i of the process_list
	if this_process is not in white_list then
		try
			tell application this_process
				quit saving yes
			end tell
		on error
			# do nothing
		end try
	end if
end repeat
EOD

# Make sure cocoaDialog is installed; if not, attempt to fix it via policy
if [[ ! -f "${ccd}" ]]; then
	echo "Keychain Repair: Attempting to install cocoaDialog via policy"
	/usr/local/jamf/bin/jamf policy -forceNoRecon -event "${ccd_trigger}"
	if [[ ! -f "${ccd}" ]]; then
		echo "Keychain Repair: Unable to install cocoaDialog, so we need to quit"
		exit 1
	else
		echo "Keychain Repair: cocoaDialog is now installed"
	fi
fi

# Get the current User
User=`python -c 'from SystemConfiguration import SCDynamicStoreCopyConsoleUser; import sys; username = (SCDynamicStoreCopyConsoleUser(None, None, None) or [None])[0]; username = [username,""][username in [u"loginwindow", None, u""]]; sys.stdout.write(username + "\n");'`

# Get the current user's home directory
UserHomeDirectory=$(/usr/bin/dscl . -read Users/"${User}" NFSHomeDirectory | awk '{print $2}')

# Prompt the User about what is about to happen and confirm intent
confirmContinue=($("${ccd}" msgbox --icon stop --title "Keychain Repair" --text "Are you sure you want to continue?" --informative-text "This utility will close all open applications and restart this computer. If you'd like to continue, click 'Close Apps and Repair' below. Any running applications with unsaved work will prompt you to save open files before closing." --float --button1 "Close Apps and Repair" --button2 "Cancel"))

# If User confirms their intent we'll continue. For cases where the User
# cancels the policy should still complete "successfully" and
# be logged that way in Casper since it's not an explicit failure
# so we will exit successfully regardless of the choice
if [[ ${confirmContinue[0]} -eq "1" ]]; then
	# Quit all running applications
	/usr/bin/osascript -e "${OSASCRIPT_COMMAND}"
	# Pause briefly to let apps quit
	sleep 10

	# Get the current User's default (login) keychain
	CurrentKeychain=$(su "${User}" -c "security list-keychains" | grep login | sed -e 's/\"//g' | sed -e 's/\// /g' | awk '{print $NF}')

	if [[ -z $CurrentKeychain ]]; then
		echo "Keychain Repair: Unable to find a login keychain for User $User"
	else
		echo "Keychain Repair: Found $UserHomeDirectory/Library/Keychains/${CurrentKeychain} - deleting"
		mv $UserHomeDirectory/Library/Keychains/$CurrentKeychain $UserHomeDirectory/Library/Keychains/$User.keychain.bkp
	fi

	# Make a new login keychain

 	# Prompt for login password
 	rv=($("${ccd}" secure-standard-inputbox --icon-file /Applications/Utilities/Keychain\ Access.app/Contents/Resources/Keychain.icns --title "Password" --no-newline --informative-text "Enter your current login password:"))
 	PASSWORD=${rv[1]}
 	# Prompt again for password to confirm
 	rv2=($("${ccd}" secure-standard-inputbox --icon-file /Applications/Utilities/Keychain\ Access.app/Contents/Resources/Keychain.icns --title "Password" --no-newline --informative-text "Verify your login password by entering it again:"))
 	PASSWORD2=${rv2[1]}

 	# Ensure passwords match
 	if [[ "${PASSWORD}" != "${PASSWORD2}" ]]; then
 		# Confirm with User that they'd like to continue
 		"${ccd}" msgbox --icon stop --title "Keychain Repair" --text "Password mismatch!" --informative-text "The two passwords you entered do not match. Please close this utility and restart from it from Self Service." --float --button1 "Close"
 		exit 0
 	fi

	# Create the new login keychain
expect <<- DONE
	set timeout -1
	spawn su "${User}" -c "security create-keychain login.keychain"
	# Look for  prompt
	expect "*?chain:*"
	# send User entered password from CocoaDialog
	send "$PASSWORD\n"
	expect "*?chain:*"
	send "$PASSWORD\r"
	expect EOF
DONE

	#Set the newly created login.keychain as the Users default keychain
	su "${User}" -c "security default-keychain -s login.keychain"

	#Unset timeout/lock behavior
	su "${User}" -c "security set-keychain-settings login.keychain"

	# Current user's Local Items keychain
	LocalItemsKeychainHash=$(ls "${UserHomeDirectory}"/Library/Keychains/ | egrep '([A-Z0-9]{8})((-)([A-Z0-9]{4})){3}(-)([A-Z0-9]{12})')

	if [[ -z $LocalItemsKeychainHash ]]; then
		echo "Keychain Repair: Unable to find a Local Items keychain"
	else
 		echo "Keychain Repair: Deleting ${UserHomeDirectory}/Library/Keychains/${LocalItemsKeychainHash}"
		rm -rf ${UserHomeDirectory}/Library/Keychains/${LocalItemsKeychainHash}
	fi

	# All done, warn the user the system is rebooting, send the command and exit
	"${ccd}" ok-msgbox --title "Keychain Repair" --text "Keychain Repair Complete" --informative-text "The Keychain Repair utility has repaired your keychain. This device must now reboot to complete the process. Please log back in with your current credentials once the system is back online." --icon sync --float --no-cancel

	exit 0
else
	echo "Keychain Repair: User '${User}' decided to cancel"
	exit 0
fi
