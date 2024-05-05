#!/bin/zsh

####################################################################################################
#
#  NoDoze - keep your Mac awake for a short amount of time.  Currently set to 120 minutes max.
#
#   This script is offered as is with no warranty or guarantee. 
#   This is my 1st script obvious from the ugly code below.  While there are better ways to accomplish what this script
#        does, it was made more for learning how to use swift dialog than anything else.
#   This was written for a specific purpose and has NOT been extensivly tested on different models or macOS versions.
#   Originally designed to keep a Mac laptop awake during a large file download/upload.  Usage is limited by Jamf Policy.
#   There are commands for Jamf as well including recon.
#   This will kill processes including dialog, jamf helper, jamf self service, and caffinate.
#   The logging is not active in this version of the script.
#
####################################################################################################
#
#   Script features
#       - Checks for the Mac to be plugged into power, will wait until this is done.
#       - User is prompted to enter a time between 1-120 minutes.
#       - User has a quit button to stop the script early
#       - Use "Say" to alert the user when the script starts and has ended (for when they step away)
#       - Uses Dialog, JamfHelper, Caffinate, and pmset
#
#   Concerns
#       - Keeping a laptop awake for extended periods of time can affect battery life and performance.
#       - Logged in computers that are unattended are a security risk when the user walks away from it.
#
#
####################################################################################################
#
# Code inspirations came from a numer of other swift dialog scipts including but not limited to:
#   @bartreardon and a lot of RTFM https://github.com/swiftDialog/swiftDialog/wiki 
#                and sample code https://github.com/swiftDialog/swiftDialog/wiki/Showcase 
#                                https://github.com/swiftDialog/swiftDialog/wiki/Example-Jamf-Scripts
#   Dan Snelson's setup your mac https://snelson.us/ and https://github.com/setup-your-mac
#   @robjschroeder and Elevate https://github.com/robjschroeder/Elevate
#   @BigMacAdmin and a variety of sample code: https://github.com/SecondSonConsulting/swiftDialogExamples/tree/main
#   Adam Codega: https://github.com/acodega/dialog-scripts/
#   Martin Piron: https://github.com/ooftee/dialog-starterKit
#
####################################################################################################

scriptVersion="0.2" # 2024/05/04 written in ugly code

# Set some basic variables
dialog="/usr/local/bin/dialog"
jamfhelpr="/System/Library/CoreServices/KeyboardSetupAssistant.app/Contents/Resources/AppIcon.icns"

## Icon to display during the AC Power warning
warnIcon="/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/AlertCautionIcon.icns"
alertIcon="/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/AlertStopIcon.icns"
jhicon="/Library/Application Support/graphics/ourlogo.png"
scriptFunctionalName="nodoze"

## Amount of time (in seconds) to allow a user to connect to AC power before moving on
## If null or 0, then the user will not have the opportunity to connect to AC power
acPowerWaitTimer="90"

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Pre-flight Check: Validate / install swiftDialog (Thanks big bunches, @acodega!)
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function dialogCheck() {

    # Get the URL of the latest PKG From the Dialog GitHub repo
    dialogURL=$(curl -L --silent --fail "https://api.github.com/repos/swiftDialog/swiftDialog/releases/latest" | awk -F '"' "/browser_download_url/ && /pkg\"/ { print \$4; exit }")

    # Expected Team ID of the downloaded PKG
    expectedDialogTeamID="PWA5E9TQ59"

    # Check for Dialog and install if not found
    if [ ! -e "/Library/Application Support/Dialog/Dialog.app" ]; then

#        updateScriptLog "PRE-FLIGHT CHECK (${scriptFunctionalName}): Dialog not found. Installing..."

        # Create temporary working directory
        workDirectory=$( /usr/bin/basename "$0" )
        tempDirectory=$( /usr/bin/mktemp -d "/private/tmp/$workDirectory.XXXXXX" )

        # Download the installer package
        /usr/bin/curl --location --silent "$dialogURL" -o "$tempDirectory/Dialog.pkg"

        # Verify the download
        teamID=$(/usr/sbin/spctl -a -vv -t install "$tempDirectory/Dialog.pkg" 2>&1 | awk '/origin=/ {print $NF }' | tr -d '()')

        # Install the package if Team ID validates
        if [[ "$expectedDialogTeamID" == "$teamID" ]]; then

            /usr/sbin/installer -pkg "$tempDirectory/Dialog.pkg" -target /
            sleep 2
            dialogVersion=$( /usr/local/bin/dialog --version )
            # updateScriptLog "PRE-FLIGHT CHECK (${scriptFunctionalName}): swiftDialog version ${dialogVersion} installed; proceeding..."

        else

            # Display a so-called "simple" dialog if Team ID fails to validate
            osascript -e 'display dialog "Please advise your Support Representative of the following error:\r\r• Dialog Team ID verification failed\r\r" with title "'${scriptFunctionalName}': Error" buttons {"Close"} with icon caution'
            updateScriptLog "PRE-FLIGHT CHECK: Team ID validation failure, exiting..."
            exit 1
            
        fi

        # Remove the temporary working directory when done
        /bin/rm -Rf "$tempDirectory"

    else

        # updateScriptLog "PRE-FLIGHT CHECK (${scriptFunctionalName}): swiftDialog version $(/usr/local/bin/dialog --version) found; proceeding..."
        echo "Need logging"

    fi

}

if [[ ! -e "/Library/Application Support/Dialog/Dialog.app" ]]; then
    dialogCheck
else
    # updateScriptLog "PRE-FLIGHT CHECK (${scriptFunctionalName}): swiftDialog version $(/usr/local/bin/dialog --version) found; proceeding..."
    echo "Need logging"
fi

#########################################################################################
# Functions
#########################################################################################

kill_process() {
    processPID="$1"
    if /bin/ps -p "$processPID" > /dev/null ; then
        /bin/kill "$processPID"
        wait "$processPID" 2>/dev/null
    fi
}

wait_for_ac_power() {
    local jamfHelperPowerPID
    jamfHelperPowerPID="$1"
    ## Loop for "acPowerWaitTimer" seconds until either AC Power is detected or the timer is up
    /bin/echo "Waiting for AC power..."
    while [[ "$acPowerWaitTimer" -gt "0" ]]; do
        if /usr/bin/pmset -g ps | /usr/bin/grep "AC Power" > /dev/null ; then
            /bin/echo "Power Check: OK - AC Power Detected"
            kill_process "$jamfHelperPowerPID"
            return
        fi
        sleep 1
        ((acPowerWaitTimer--))
    done
    kill_process "$jamfHelperPowerPID"
    sysRequirementErrors+=("Is connected to AC power")
    /bin/echo "Power Check: ERROR - No AC Power Detected"
}

validate_power_status() {
    ## Check if device is on battery or ac power
    ## If not, and our acPowerWaitTimer is above 1, allow user to connect to power for specified time period
    if /usr/bin/pmset -g ps | /usr/bin/grep "AC Power" > /dev/null ; then
        /bin/echo "Power Check: OK - AC Power Detected"
    else
        if [[ "$acPowerWaitTimer" -gt 0 ]]; then
            "/Library/Application Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper" -windowType utility -title "Waiting for AC Power Connection" -icon "$jhicon" -description "Please connect your computer to power using an AC power adapter. This process will continue once AC power is detected." &
            wait_for_ac_power "$!"
        else
            sysRequirementErrors+=("Is connected to AC power")
            /bin/echo "Power Check: ERROR - No AC Power Detected"
        fi
    fi
}

function killProcess() {
    process="$1"
    if process_pid=$( pgrep -a "${process}" 2>/dev/null ) ; then
#        updateScriptLog "Attempting to terminate the '$process' process …"
#        updateScriptLog "(Termination message indicates success.)"
        kill "$process_pid" 2> /dev/null
#        if pgrep -a "$process" >/dev/null ; then
#            updateScriptLog "ERROR: '$process' could not be terminated."
#        fi
#    else
#        updateScriptLog "The '$process' process isn't running."
    fi
}

## Run system requirement checks
validate_power_status

# delete any caffeinate currently running
killProcess "caffeinate"

# Quit Self Service after starting - too distracting
killProcess "Self Service"

# just to be safe
killall "Dialog"

# check for power
if [[ $(pmset -g ps | head -1) =~ "AC Power" ]]; then
  echo "power on!"
fi

# Dialog Icon
icon="/System/Library/CoreServices/KeyboardSetupAssistant.app/Contents/Resources/AppIcon.icns"
awakeDialogTitle="Set the timer"
awakeDialogMessage="How many minutes do you need this to run? (Max 120) \n\n We will tell you when the timer starts and ends. Check your volume before selecting the amount of time."
nodozeDialogTitle="staying awake"
nodozeDialogMessage="Keeping your Mac awake for"
button1text="ok"
button2text="cancel"
quitButtontext="quit"

# attempt at a drop down did  not pan out
selectWords="Pick how many minutes"
selectValueList="30,60,90,120"

# Create `overlayicon` from Self Service's custom icon (thanks, @meschwartz!)
xxd -p -s 260 "$(defaults read /Library/Preferences/com.jamfsoftware.jamf self_service_app_path)"/Icon$'\r'/..namedfork/rsrc | xxd -r -p > /var/tmp/overlayicon.icns
overlayicon="/var/tmp/overlayicon.icns"

#
# Dialog to ask how much time to run and some instructions
# see regex below to limit to a number between 1 and 121
#

timrDialogCMD="$dialog -p \
--title \"$awakeDialogTitle\" \
--titlefont size=22 \
--message \"$awakeDialogMessage\" \
--icon \"$icon\" \
--infotext \"$scriptVersion\" \
--iconsize 135 \
--overlayicon \"$overlayicon\" \
--button1text \"$button1text\" \
--button2text \"$button2text\" \
--moveable \
--width 425 \
--height 285 \
--textfield \"Time\",regex=\"\\b([1-9]|[1-9][0-9]|1[01][0-9]|12[0-1])\b\",regexerror=\"Pick from 1 - 120 minutes\" \
--messagefont size=12 \
--messagealignment left \
--position topright \ "
returncode=$?

output=$(eval "$timrDialogCMD")
thetime=$(echo $output | grep Time | awk '{print $NF}')

# Echo used to test variables
# echo "The output is" $results 
# echo "The other output is" $thetime 

nodozeSeconds=$(( ${thetime} * 60 ))

case ${returncode} in
    0)  echo "Pressed Button 1"
        ## Process exit code 0 scenario here

        # Ensure computer does not go to sleep while running this script, which is the point of the script (thanks, @grahampugh!)
        caffeinate -dimsu -w $$ &

        # Say we are starting
        say "Starting Awake Timer"

        #
        # Dialog to ask how much time to run and some instructions
        # see regex below to limit to a number between 1 and 121
        #

        nodozeCMD="$dialog -p \
            --title \"$nodozeDialogTitle\" \
            --titlefont size=15 \
            --message \"$nodozeDialogMessage\" \
            --icon \"$icon\" \
            --iconsize 5 \
            --overlayicon \"$overlayicon\" \
            --button1text \"$quitButtontext\" \
            --moveable \
            --width 300 \
            --height 150 \
            --messagefont size=14 \
            --messagealignment left \
            --position topright \
            --timer $nodozeSeconds "

        returncode2=$?
        nodozer=$(eval "$nodozeCMD")
        echo "The last output is" $thetime 
        case ${returncode2} in
        0)  echo "Pressed Button 1"
        ## Process exit code 0 scenario here
            killProcess "caffeinate"
            say "Awake timer has ended"
            sudo jamf recon

        ;;

    *)  echo "Something else happened. exit code ${returncode}"
        ## Catch all processing
            killProcess "caffeinate"
            exit 0 
        ;;
        esac

        ;;

esac

# make sure script exits cleanly otherwise Self Service will complain if it's anything other than 0
exit 0 
