# nodoze

A swift dialog script to keep the Mac awake for a standard user when you have a special need.

NoDoze - keep your Mac awake for a short amount of time.  Currently set to 120 minutes max.

   This script is offered as is with no warranty or guarantee. 
   This is my 1st script obvious from the ugly code below.  While there are better ways to accomplish what this script
        does, it was made more for learning how to use swift dialog than anything else.
   This was written for a specific purpose and has NOT been extensivly tested on different models or macOS versions.
   Originally designed to keep a Mac laptop awake during a large file download/upload.  Usage is limited by Jamf Policy.
   There are commands for Jamf as well including recon.
   This will kill processes including dialog, jamf helper, jamf self service, and caffinate.
   The logging is not active in this version of the script.
