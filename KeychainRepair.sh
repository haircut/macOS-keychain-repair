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
#      modified: 2015-02-27
#
#####################################

# Location of cocoaDialog binary
# cocoaDialog provides a "gui" for the repair tool. It should be installed at
# the path below. NOTE: This must point to the actual binary inside the app bundle
ccd="/path/to/cocoaDialog.app/Contents/MacOS/cocoaDialog"
# Location of Quit-All-Apps
# Quit-All-Apps is a small app created in Automator that will close all open applications
# EXCEPT Self Service after providing the user the opportunity to save work
qaa="/path/to/Quit-All-Apps.app"

# Make sure cocoaDialog is installed; if not, attempt to fix it via policy
# If the binary is not found, we call a Casper policy with a custom trigger "installcocoaDialog"
# to attempt to install it.
if [[ ! -f "${ccd}" ]]; then
     echo "Keychain Repair: Attempting to install cocoaDialog via policy"
     /usr/sbin/jamf policy -forceNoRecon -event installCocoaDialog
     if [[ ! -f "${ccd}" ]]; then
          echo "Keychain Repair: Unable to install cocoaDialog, so we need to quit"
          exit 1
     else
          echo "Keychain Repair: cocoaDialog is now installed"
     fi
fi

# Make sure Quit-All-Apps is installed; if not, attempt to fix it via policy
# If the app is not found, we call a Casper policy with a custom trigger "installQuitAllApps"
# to attempt to install it.
if [[ -z "${qaa}" ]]; then
     echo "Keychain Repair: Attempting to install Quit-All-Apps via policy"
     /usr/sbin/jamf policy -forceNoRecon -event installQuitAllApps
     if [[ -z "${ccd}" ]]; then
          echo "Keychain Repair: Unable to install Quit-All-Apps, so we need to quit"
          exit 1
     else
          echo "Keychain Repair: Quit-All-Apps is now installed"
     fi
fi

# Get the current User
User=$(/usr/bin/who | /usr/bin/grep console | /usr/bin/awk '{print $1}')

# Get the current user's home directory
UserHomeDirectory=$(/usr/bin/dscl . -read Users/"${User}" NFSHomeDirectory | awk '{print $2}')

# Prompt the User about what is about to happen and confirm intent
confirmContinue=($("${ccd}" msgbox --icon stop --title "Keychain Repair" --text "Are you sure you want to continue?" --informative-text "This utility will close all open applications and restart this computer. If you'd like to continue, click 'Close Apps and Repair' below. Any running applications with unsaved work will prompt you to save open files before closing." --float --button1 "Close Apps and Repair" --button2 "Cancel"))

# If User confirms their intent we'll continue. For cases where the User
# cancels the policy should still complete "successfully" and
# be logged that way in Casper since it's not an explicit failure
# so we will exit successfully regardless of the choice
if [[ ${confirmContinue[0]} -eq "1" ]]; then
     # User Quit-All-Apps to close all running applications except Self Service
     # while prompting User to save open work
     /usr/bin/open "${qaa}"
     # Pause briefly to let Quit-All-Apps open and begin closing apps
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

     # Prompt for UNCA Security password
     rv=($("${ccd}" secure-standard-inputbox --icon-file /Applications/Utilities/Keychain\ Access.app/Contents/Resources/Keychain.icns --title "Active Directory Password" --no-newline --informative-text "Enter your current Active Directory password:"))
     PASSWORD=${rv[1]}
     # Prompt again for UNCA Security password to confirm
     rv2=($("${ccd}" secure-standard-inputbox --icon-file /Applications/Utilities/Keychain\ Access.app/Contents/Resources/Keychain.icns --title "Active Directory Password" --no-newline --informative-text "Verify your Active Directory password by entering it again:"))
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

     # Current user's Local Items keychain
     LocalItemsKeychainHash=$(ls "${UserHomeDirectory}"/Library/Keychains/ | egrep '([A-Z0-9]{8})((-)([A-Z0-9]{4})){3}(-)([A-Z0-9]{12})')

     if [[ -z $LocalItemsKeychainHash ]]; then
          echo "Keychain Repair: Unable to find a Local Items keychain"
     else
          echo "Keychain Repair: Deleting ${UserHomeDirectory}/Library/Keychains/${LocalItemsKeychainHash}"
          rm -rf ${UserHomeDirectory}/Library/Keychains/${LocalItemsKeychainHash}
     fi

     # All done, warn the user the system is rebooting, send the command and exit
     "${ccd}" ok-msgbox --title "Keychain Repair" --text "Keychain Repair Complete" --informative-text "The Keychain Repair utility has repaired your keychain. This device must now reboot to complete the process. Please log back in with your current Active Directory credentials once the system is back online." --icon sync --float --no-cancel

     shutdown -r now

     exit 0
else
     echo "Keychain Repair: User '${User}' decided to cancel"
     exit 0
fi
