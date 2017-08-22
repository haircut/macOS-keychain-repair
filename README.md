# macOS Keychain Repair
##Keychain repair script

I use this "utility" (really a shell script) to perform the following:

- Back up the current user's login keychain to ~/Library/Keychains/[username].keychain.bkp
- Delete the current user's login.keychain
- If present, delete the Local Items keychain
- Create a new login keychain secured with the user's current AD password
- Reboot the system

*Better documentation forthcoming*

## In general...

1. Install cocoaDialog to a known location. I do this during imaging. I use it for many tasks in my environment so I drop it in `/Library/Application Support/[INSTITUTION NAME]/`
3. Create a Casper policy with custom trigger "installCocoaDialog" to repair broken/missing/etc cocoaDialog locations. The Keychain Repair script will use call this policy via the custom trigger if cocoaDialog is not found, so the policy should simply re-install it.
5. Customize the KeychainRepair.sh script. It's fairly well commented.
6. Upload KeychainRepair.sh to your JSS and create a Self Service policy to run the script.
