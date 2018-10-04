#!/bin/bash
#
# Calculates how long it takes to get to a desktop from cold on OSX
# Mark J Swift
sv_CodeVersion="1.0.9" 

# ---

# How long we should run the script in seconds
iv_MaxRuntimeSecs=2700

# How many initial reboots should we do in order to time how long it takes to shutdown
iv_ShutdownTimingsMax=3

# How many iterations we should do before guessing at a start-up delay
iv_StartupDelayTimingsMin=3

# How long we should leave the Mac powered-off before powering on again (in seconds)
# Should be set to be about 5 seconds longer than the expected start-up delay
# This is altered when an actual startup-delay has been pre-calculated.
iv_LeavePoweredOffSecs=20

# How long we should wait at the desktop before shutting down
# Just enough time for things to settle down
iv_WaitIdleSecs=5

# How accurate is the scheduler at powering up (in units of seconds)
iv_ScheduleUnitOfAccuracy=60

# ---

# Take a note when this script started running
sv_ThisScriptStartEpoch=$(date -u "+%s")

# Full souce of this script
sv_ThisScriptFilePath="${0}"

# Path to this script
sv_ThisScriptDirPath="$(dirname "${sv_ThisScriptFilePath}")"

# Change working directory
cd "${sv_ThisScriptDirPath}"

# Filename of this script
sv_ThisScriptFileName="$(basename "${sv_ThisScriptFilePath}")"

# Filename without extension
sv_ThisScriptName="$(echo ${sv_ThisScriptFileName} | sed 's|\.[^.]*$||')"

# ---

# Get user name
sv_ThisUserName="$(whoami)"

# Get user home
sv_ThisUserHomeDirPath=$(eval echo ~${sv_ThisUserName})

# ---

# Check if user is an admin (returns "true" or "false")
if [ "$(dseditgroup -o checkmember -m "${sv_ThisUserName}" admin | cut -d" " -f1)" = "yes" ]
then
  bv_ThisUserIsAdmin="true"
else
  bv_ThisUserIsAdmin="false"
fi

# ---

if test -z "$(pmset -g batt | grep 'AC Power')"
then
  echo >&2 "ERROR: Cannot run script while on battery power."
  exit 0
fi

if [ "${bv_ThisUserIsAdmin}" = "false" ]
then
  echo >&2 "ERROR: You must be an admin to run this script."
  exit 0
fi

if test -z "$(defaults 2>/dev/null read /Library/Preferences/com.apple.loginwindow autoLoginUser)"
then
  echo >&2 "ERROR: Please enable auto-login before running this script."
  exit 0
fi

# ---

# timezone for executing PHP date functions
sv_TimeZone="Europe/London"

# init string for executing PHP commands
sv_PHPinit=$(php -r 'if (floatval(phpversion()) >= 5.1){echo "date_default_timezone_set(\"'${sv_TimeZone}'\");";}')

# info about this workstation
sv_WorkstationModelVersion=$(sysctl -n hw.model)

sv_BuildVersionStampAsString="$(sw_vers -buildVersion)"
sv_SystemVersionStampAsString="$(sw_vers -productVersion)"

# ---

# send message to log file and stdout
nf_logmessage()   # messagetxt
{
  echo "$(date): ${1}" | tee -a "${sv_ThisScriptDirPath}"/${sv_ThisScriptName}.log >/dev/null
  echo >&2 "${1}"
}

# Schedule event for specified EPOCH time. Identify the event with a unique TAG.
# WAKETYPE can be one of sleep, wake, poweron, shutdown, wakeorpoweron
nf_schedule4epoch()   # TAG WAKETYPE EPOCH
{
  local iv_SchedEpoch
  local sv_SchedLine
  local iv_NowEpoch

  sv_Tag=${1}
  sv_WakeType=${2}
  iv_SchedEpoch=${3}

  iv_NowEpoch=$(date -u "+%s")

  if [ ${iv_NowEpoch} -lt ${iv_SchedEpoch} ]
  then
    # check there isnt a named scheduled already
    pmset -g sched | grep -i "${sv_WakeType}" | grep -i "${sv_Tag}" | tr -s " " | cut -d " " -f5-6 | while read sv_SchedLine
    do
      pmset schedule cancel ${sv_WakeType} "${sv_SchedLine}" "${sv_Tag}" 2>/dev/null
    done

    sv_SchedLine=$(date -r ${iv_SchedEpoch} "+%m/%d/%y %H:%M:%S")
    pmset schedule ${sv_WakeType} "${sv_SchedLine}" "${sv_Tag}"
    nf_logmessage "DEBUG: Schedule ${sv_WakeType} at ${sv_SchedLine}"
    
  else
    nf_logmessage "DEBUG: Schedule ${iv_SchedEpoch} is gt than now ${iv_NowEpoch}"
    
  fi
}

nf_MeanValue()   # SourceDataFilePath - returns mean value, excluding anomalous data
{  
  local iv_DeviationLimit
  local iv_DeviationValue
  local iv_MaxChauvenetRatioSquared
  local iv_MeanValue
  local iv_ProcessedDataCount
  local iv_Sum
  local iv_ValidDataCount
  local sv_ThisFuncTempDirPath

  sv_SourceDataFilePath="${1}"

  # ---
  
  # Fixed value of 2.24 for the maximum permissible ratio of deviation to standard deviation
  # for Chauvenet’s criterion. This is Optimal for a dataset of 20 values
  # 
  iv_MaxChauvenetRatioSquared=5
  
  # ---

  # Create a temporary directory private to this function
  sv_ThisFuncTempDirPath="$(mktemp -dq /tmp/${sv_ThisScriptFileName}-XXXXXXXX)"

  # ---

  # Make a copy of the source data
  cp "${sv_SourceDataFilePath}" "${sv_ThisFuncTempDirPath}"/ValidData.txt
  
  # Count the data
  iv_ValidDataCount=$(cat "${sv_ThisFuncTempDirPath}"/ValidData.txt | wc -l | tr -d " ")

  # Process data for anomalies using Chauvenet's criterion
  iv_ProcessedDataCount=0
  iv_Pass=1
  while [ ${iv_ValidDataCount} -ne ${iv_ProcessedDataCount} ]
  do
    nf_logmessage "Checking data (pass ${iv_Pass})"
    iv_ValidDataCount=$(cat "${sv_ThisFuncTempDirPath}"/ValidData.txt | wc -l | tr -d " ")
    
    # Calculate the sum of all data
    iv_Sum=0
    while read iv_Value
    do
      iv_Sum=$((${iv_Sum}+${iv_Value}))
    done <"${sv_ThisFuncTempDirPath}"/ValidData.txt

    # Calculate standard deviation ( actually, sd.n.n.n )
    iv_DeviationValue=0
    while read iv_Value
    do
      iv_DeviationValue=$((${iv_DeviationValue}+(${iv_Sum}-${iv_Value}*${iv_ValidDataCount})*(${iv_Sum}-${iv_Value}*${iv_ValidDataCount})))
    done <"${sv_ThisFuncTempDirPath}"/ValidData.txt

    iv_DeviationLimit=$((${iv_MaxChauvenetRatioSquared}*${iv_DeviationValue}))

    rm -f "${sv_ThisFuncTempDirPath}"/ProcessedData.txt
    touch "${sv_ThisFuncTempDirPath}"/ProcessedData.txt

    while read iv_Value
    do
      if [ $(( ${iv_ValidDataCount}*(${iv_Sum}-${iv_Value}*${iv_ValidDataCount})*(${iv_Sum}-${iv_Value}*${iv_ValidDataCount}) )) -gt ${iv_DeviationLimit} ]
      then
        nf_logmessage "Anomalous value ${iv_Value} excluded from data (value is an outliner)"
      else
        echo "${iv_Value}" >> "${sv_ThisFuncTempDirPath}"/ProcessedData.txt
      fi
    done <"${sv_ThisFuncTempDirPath}"/ValidData.txt

    iv_ProcessedDataCount=$(cat "${sv_ThisFuncTempDirPath}"/ProcessedData.txt | wc -l | tr -d " ")
    mv -f "${sv_ThisFuncTempDirPath}"/ProcessedData.txt "${sv_ThisFuncTempDirPath}"/ValidData.txt

    # Not sure if you're supposed to iterate Chauvenet's criterion
    iv_Pass=$((${iv_Pass}+1))
  done

  # Calculate the sum of all valid data
  iv_Sum=0
  while read iv_Value
  do
    iv_Sum=$((${iv_Sum}+${iv_Value}))
  done <"${sv_ThisFuncTempDirPath}"/ValidData.txt

  # Calculate the mean value (rounded up)
  iv_ValidDataCount=$(cat "${sv_ThisFuncTempDirPath}"/ValidData.txt | wc -l | tr -d " ")
  nf_logmessage "Mean calculated using ${iv_ValidDataCount} valid data values"

  iv_MeanValue=$(( (${iv_Sum}+${iv_Sum}+${iv_ValidDataCount})/(${iv_ValidDataCount}+${iv_ValidDataCount}) ))

  # Remove temporary files
  rm -fR ${sv_ThisFuncTempDirPath}

  echo "${iv_MeanValue}"

}

if [ "${sv_ThisUserName}" != "root" ]
then
  # We are running as a normal user
  if test -f /Library/LaunchDaemons/${sv_ThisScriptName}-SchedulePowerOn.plist
  then
    # Script already installed - so lets do what we need to do
    iv_InstallTimeEpoch=$(stat -f "%m" ${sv_ThisUserHomeDirPath}/Library/LaunchAgents/${sv_ThisScriptName}-Launcher.plist)

    iv_RuntimeSecs=$((${sv_ThisScriptStartEpoch}-${iv_InstallTimeEpoch}))

    if test -f "${sv_ThisScriptDirPath}"/${sv_ThisScriptName}-tmp/ShutdownTime.txt
    then
      # We have estimated how long it takes to shutdown - so do the next bit

      if test -f "${sv_ThisScriptDirPath}"/${sv_ThisScriptName}-tmp/ColdStart2DesktopTimings.txt
      then
        # We have already started coldstart timings
          
        # When were we sheduled to power on?
        iv_LastPowerOnEpoch=$(stat -f "%m" "${sv_ThisScriptDirPath}"/${sv_ThisScriptName}-tmp/SchedulePowerOn.txt)

        # How long did it take to start logging after boot?
        sv_BootLogTimeString=$(sysctl kern.boottime | tr -d "\n" | tr "}" "\n" | tr "=" "\n" | tail -n1)
        nf_logmessage "DEBUG: kern.boottime ${sv_BootLogTimeString}"
        iv_BootLogEpoch=$(php -r ${sv_PHPinit}'echo strtotime("'"${sv_BootLogTimeString}"'"), "\n";')
        if [ -n "${iv_BootLogEpoch}" ]
        then
          iv_StartupDelaySecs=$((${iv_BootLogEpoch}-${iv_LastPowerOnEpoch}))
          
        else
          iv_StartupDelaySecs=0
          
        fi

        # How long did it take to get to a useable desktop?
        iv_ColdStart2DesktopSecs=$((${sv_ThisScriptStartEpoch}-${iv_LastPowerOnEpoch}))

        if [ ${iv_StartupDelaySecs} -ge 0 ]
        then
          if [ ${iv_ColdStart2DesktopSecs} -ge 0 ]
          then
            if [ -n "${iv_BootLogEpoch}" ]
            then
              nf_logmessage "INFO: STARTUPDELAY ${iv_StartupDelaySecs} seconds."
              echo ${iv_StartupDelaySecs} >> "${sv_ThisScriptDirPath}"/${sv_ThisScriptName}-tmp/StartupDelayTimings.txt
            fi

            nf_logmessage "INFO: COLDSTART2DESKTOP ${iv_ColdStart2DesktopSecs} seconds."
            echo ${iv_ColdStart2DesktopSecs} >> "${sv_ThisScriptDirPath}"/${sv_ThisScriptName}-tmp/ColdStart2DesktopTimings.txt
          else
            # we have prematurely switched workstation on in order to stop the timings
            nf_logmessage "INFO: User cancelled script (1)."
            iv_MaxRuntimeSecs=0
          fi
          
        else
          # we have prematurely switched workstation on in order to stop the timings
          nf_logmessage "INFO: User cancelled script (2)."
          iv_MaxRuntimeSecs=0
            
        fi

        # Get StartupDelay if we've calculated it
        if test -f "${sv_ThisScriptDirPath}"/${sv_ThisScriptName}-tmp/StartupDelayTime.txt
        then
          iv_StartupDelaySecs=$(cat "${sv_ThisScriptDirPath}"/${sv_ThisScriptName}-tmp/StartupDelayTime.txt | head -n1)
          iv_LeavePoweredOffSecs=$((${iv_StartupDelaySecs}+${iv_WaitIdleSecs}))
          
        else
          iv_StartupDelayTimingsCount=$(cat "${sv_ThisScriptDirPath}"/${sv_ThisScriptName}-tmp/StartupDelayTimings.txt | wc -l)
          if [ ${iv_StartupDelayTimingsCount} -eq ${iv_StartupDelayTimingsMin} ]
          then
            # We have enough reboot timings to calculate a reasonable StartupDelay
          
            iv_TotalSecs=0
            iv_Count=0
            while read iv_Secs
            do
              iv_TotalSecs=$(( ${iv_TotalSecs} + ${iv_Secs} ))
              iv_Count=$(( ${iv_Count} + 1 ))
            done <"${sv_ThisScriptDirPath}"/${sv_ThisScriptName}-tmp/StartupDelayTimings.txt
            iv_AverageSecs=$(( ${iv_TotalSecs} / ${iv_Count} ))
            echo ${iv_AverageSecs} > "${sv_ThisScriptDirPath}"/${sv_ThisScriptName}-tmp/StartupDelayTime.txt
        
            nf_logmessage "INFO: Initial average STARTUPDELAY ${iv_AverageSecs} seconds, measured over ${iv_Count} samples."

            iv_StartupDelaySecs=${iv_AverageSecs}
            
            # Get the over-estimated shutdown time
            iv_ShutdownTimeSecs=$(cat "${sv_ThisScriptDirPath}"/${sv_ThisScriptName}-tmp/ShutdownTime.txt | head -n1)
            
            # Recalculate taking in to account the start-up delay
            iv_ShutdownTimeSecs=$((${iv_ShutdownTimeSecs}-${iv_StartupDelaySecs}))

            echo ${iv_ShutdownTimeSecs} > "${sv_ThisScriptDirPath}"/${sv_ThisScriptName}-tmp/ShutdownTime.txt
        
            nf_logmessage "INFO: Recalculated shutdown delay to be ${iv_ShutdownTimeSecs} seconds."
            
            iv_LeavePoweredOffSecs=$((${iv_StartupDelaySecs}+${iv_WaitIdleSecs}))
            nf_logmessage "INFO: Leave powered off value now set to be ${iv_LeavePoweredOffSecs} seconds."

          fi
        fi

      else
        # We haven't started coldstart timings

        touch "${sv_ThisScriptDirPath}"/${sv_ThisScriptName}-tmp/ColdStart2DesktopTimings.txt
        touch "${sv_ThisScriptDirPath}"/${sv_ThisScriptName}-tmp/StartupDelayTimings.txt
      fi

      if [ ${iv_RuntimeSecs} -lt ${iv_MaxRuntimeSecs} ]
      then
        # wait around a bit for things to settle down
        sleep ${iv_WaitIdleSecs}

        # Get the over-estimated shutdown time
        iv_ShutdownTimeSecs=$(cat "${sv_ThisScriptDirPath}"/${sv_ThisScriptName}-tmp/ShutdownTime.txt | head -n1)
          
        # Calculate when we should next power on
        iv_NextPowerOnEpoch=$(($(date -u "+%s")+${iv_ShutdownTimeSecs}+${iv_LeavePoweredOffSecs}))
          
        # Round up to the nearest unit of accuracy
        iv_NextPowerOnEpoch=$((${iv_NextPowerOnEpoch}+${iv_ScheduleUnitOfAccuracy}-(${iv_NextPowerOnEpoch} % ${iv_ScheduleUnitOfAccuracy})))
      
        # Dont allow schedules within 1 unit of accuracy of current time ( sometimes they are ignored )
        iv_ClosestAllowablePowerOnEpoch=$((  ($(date -u "+%s")/${iv_ScheduleUnitOfAccuracy} +2) * ${iv_ScheduleUnitOfAccuracy}  ))
        if [ ${iv_NextPowerOnEpoch} -lt ${iv_ClosestAllowablePowerOnEpoch} ]
        then
          iv_NextPowerOnEpoch=${iv_ClosestAllowablePowerOnEpoch}
        fi

        sv_CurrentSched="$(pmset -g sched)"

        # trigger root LaunchDaemon to schedule power-on
        #touch -t $(date -jf "%s" ${iv_NextPowerOnEpoch} "+%Y%m%d%H%M.%S") "${sv_ThisScriptDirPath}"/${sv_ThisScriptName}-tmp/SchedulePowerOn.txt
        touch -t $(php -r ${sv_PHPinit}'echo date("ymdHi.s",'${iv_NextPowerOnEpoch}'), "\n";') "${sv_ThisScriptDirPath}"/${sv_ThisScriptName}-tmp/SchedulePowerOn.txt

        # wait until root LaunchDaemon has scheduled a poweron
        while [ "$(pmset -g sched)" = "${sv_CurrentSched}" ]
        do
          sleep 1
        done

        # applescript code to shut down gracefully
        /usr/bin/osascript -e 'tell application "System Events" to shut down'

      else
        # We have finished collecting reboot timings, so calculate the mean value(s)
          
        # Calculate the averages - discarding 'bad' data
        iv_MeanStartupDelay=$(nf_MeanValue "${sv_ThisScriptDirPath}"/${sv_ThisScriptName}-tmp/StartupDelayTimings.txt)        
        iv_MeanColdStart2Desktop=$(nf_MeanValue "${sv_ThisScriptDirPath}"/${sv_ThisScriptName}-tmp/ColdStart2DesktopTimings.txt)
             
        # Log the results     
        nf_logmessage "INFO: Workstation Model ${sv_WorkstationModelVersion} - OS Version ${sv_SystemVersionStampAsString} - OS Build ${sv_BuildVersionStampAsString}"
        nf_logmessage "INFO: Average STARTUPDELAY ${iv_MeanStartupDelay} seconds."
        nf_logmessage "INFO: Average COLDSTART2DESKTOP ${iv_MeanColdStart2Desktop} seconds."

        # All done, so UNINSTALL the script

        nf_logmessage "INFO: Uninstalling ${sv_ThisScriptName} (per-user LaunchAgent)"
        rm -f ${sv_ThisUserHomeDirPath}/Library/LaunchAgents/${sv_ThisScriptName}-Launcher.plist

        # signal root LaunchDaemon to uninstall
        rm -f "${sv_ThisScriptDirPath}"/${sv_ThisScriptName}-tmp/SchedulePowerOn.txt

        # wait until LauncDaemon has uninstalled too
        while [ -e /Library/LaunchDaemons/${sv_ThisScriptName}-SchedulePowerOn.plist ]
        do
          sleep 1
        done

        # Delete temporary files
        rm -fR "${sv_ThisScriptDirPath}"/${sv_ThisScriptName}-tmp

        nf_logmessage "INFO: Script ${sv_ThisScriptName} has been uninstalled"

        # applescript code to restart gracefully
        /usr/bin/osascript -e 'tell application "System Events" to restart'

      fi
      
    else

      if ! test -f "${sv_ThisScriptDirPath}"/${sv_ThisScriptName}-tmp/ShutdownTimings.txt
      then
        # We haven't started timing shutdowns
        
        # Indicate when the script really started
        touch ${sv_ThisUserHomeDirPath}/Library/LaunchAgents/${sv_ThisScriptName}-Launcher.plist
        
        # wait around a bit for things to settle down
        sleep ${iv_WaitIdleSecs}

        # Initialise the timings file
        touch "${sv_ThisScriptDirPath}"/${sv_ThisScriptName}-tmp/ShutdownTimings.txt
        
      else
        iv_ShutdownTimingsEpoch=$(stat -f "%m" "${sv_ThisScriptDirPath}"/${sv_ThisScriptName}-tmp/ShutdownTimings.txt)
        
        # When did we start logging after boot?
        sv_BootLogTimeString=$(sysctl kern.boottime | tr -d "\n" | tr "}" "\n" | tr "=" "\n" | tail -n1)
        iv_BootLogEpoch=$(php -r ${sv_PHPinit}'echo strtotime("'"${sv_BootLogTimeString}"'"), "\n";')
        if [ -z "${iv_BootLogEpoch}" ]
        then
          iv_BootLogEpoch=${sv_ThisScriptStartEpoch}
        fi

        # Estimate how long it took to shutdown? (doesn't take account of start-up delay so will be on plus side)
        iv_ShutdownTimingsSecs=$((${iv_BootLogEpoch}-${iv_ShutdownTimingsEpoch}))
        nf_logmessage "INFO: shutdown delay (over-estimated) ${iv_ShutdownTimingsSecs} seconds."
        echo ${iv_ShutdownTimingsSecs} >> "${sv_ThisScriptDirPath}"/${sv_ThisScriptName}-tmp/ShutdownTimings.txt
    
      fi
      
      iv_ShutdownTimingsCount=$(cat "${sv_ThisScriptDirPath}"/${sv_ThisScriptName}-tmp/ShutdownTimings.txt | wc -l)
      if [ ${iv_ShutdownTimingsCount} -ge ${iv_ShutdownTimingsMax} ]
      then
        # We have finished collecting reboot timings, so calculate the average value
        iv_TotalSecs=0
        iv_Count=0
        while read iv_Secs
        do
          iv_TotalSecs=$(( ${iv_TotalSecs} + ${iv_Secs} ))
          iv_Count=$(( ${iv_Count} + 1 ))
        done <"${sv_ThisScriptDirPath}"/${sv_ThisScriptName}-tmp/ShutdownTimings.txt
        iv_AverageSecs=$(( ${iv_TotalSecs} / ${iv_Count} ))
        echo ${iv_AverageSecs} > "${sv_ThisScriptDirPath}"/${sv_ThisScriptName}-tmp/ShutdownTime.txt
        
        nf_logmessage "INFO: Initial shutdown delay guess ${iv_AverageSecs} seconds, measured over ${iv_Count} samples."

      fi
    
      # applescript code to restart gracefully
      /usr/bin/osascript -e 'tell application "System Events" to restart'

    fi
    
  else
    # Script not installed - so lets install it
    nf_logmessage "INFO: Installing ${sv_ThisScriptName} - ${sv_CodeVersion}"
    
    mkdir -p "${sv_ThisScriptDirPath}"/${sv_ThisScriptName}-tmp

    # Create watch file
    touch -t 200601010000.00 "${sv_ThisScriptDirPath}"/${sv_ThisScriptName}-tmp/SchedulePowerOn.txt
    
    echo ""
    echo "If asked, enter the password for user '"${sv_ThisUserName}"'"
    echo ""
    sudo "${sv_ThisScriptFilePath}"

    if test -f /Library/LaunchDaemons/${sv_ThisScriptName}-SchedulePowerOn.plist
    then
      mkdir -p ${sv_ThisUserHomeDirPath}/Library/LaunchAgents

      cat << EOF > ${sv_ThisUserHomeDirPath}/Library/LaunchAgents/${sv_ThisScriptName}-Launcher.plist
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>${sv_ThisScriptName}-timer</string>
	<key>ProgramArguments</key>
	<array>
		<string>${sv_ThisScriptFilePath}</string>
	</array>
	<key>RunAtLoad</key>
	<true/>
</dict>
</plist>
EOF
    
      echo "${sv_ThisScriptName} installed OK."
      echo ""
      echo "PLEASE READ CAREFULLY!"
      echo "To begin the timings do the following:"
      echo "1. Quit all running applications"
      echo "2. Close all windows,"
      echo "3. Reboot."
      echo ""
      echo "Note: during the timing process, the workstation will power off,"
      echo "      then auto power on many times before finishing."
      echo ""
      echo "The whole process will take $((${iv_MaxRuntimeSecs}/60)) minutes to complete."
      echo ""
      echo "To stop the process prematurely, wait for the workstation to switch off,"
      echo "then immediately switch it on again."
      echo ""
      echo "If this does not work, boot into Single-User mode and delete the"
      echo "following files:"
      echo "  ${sv_ThisUserHomeDirPath}/Library/LaunchAgents/${sv_ThisScriptName}-Launcher.plist"
      echo "  /Library/LaunchDaemons/${sv_ThisScriptName}-SchedulePowerOn.plist"
      echo ""
      
    else
      nf_logmessage "INFO: ${sv_ThisScriptName} failed to install - everything is as it was."
      
    fi
  fi

else
  # We are root
  if ! test -f /Library/LaunchDaemons/${sv_ThisScriptName}-SchedulePowerOn.plist
  then
    # LaunchDaemon not installed yet - so lets install it
    cat << EOF > /Library/LaunchDaemons/${sv_ThisScriptName}-SchedulePowerOn.plist
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>${sv_ThisScriptName}-SchedulePowerOn</string>
	<key>ProgramArguments</key>
	<array>
		<string>${sv_ThisScriptFilePath}</string>
	</array>
	<key>WatchPaths</key>
	<array>
	<string>${sv_ThisScriptDirPath}/${sv_ThisScriptName}-tmp/SchedulePowerOn.txt</string>
	</array>
	<key>OnDemand</key>
	<true/>
	<key>UserName</key>
	<string>root</string>
</dict>
</plist>
EOF
    chmod 644 /Library/LaunchDaemons/${sv_ThisScriptName}-SchedulePowerOn.plist

    # make sure we are not held up by a User Agreement
    rm -f /Library/Security/PolicyBanner*

    # Maybe we should disable Spotlight?
    # touch /.metadata_never_index

    # We will leave it up to the user to reboot
    
  else
    # We are already installed
    
    if ! test -f "${sv_ThisScriptDirPath}"/${sv_ThisScriptName}-tmp/SchedulePowerOn.txt
    then
      # The watch file has been deleted, we must want to uninstall
      
      # Delete LaunchDaemon. The user process will then shutdown gracefully.
      nf_logmessage "INFO: Uninstalling ${sv_ThisScriptName} (system-level LaunchDaemon)"
      rm -f /Library/LaunchDaemons/${sv_ThisScriptName}-SchedulePowerOn.plist
      
    else
      # schedule a power on. The user process will then shutdown gracefully.
      
      iv_NextPowerOnEpoch=$(stat -f "%m" "${sv_ThisScriptDirPath}"/${sv_ThisScriptName}-tmp/SchedulePowerOn.txt)
      nf_schedule4epoch ${sv_ThisScriptName} poweron ${iv_NextPowerOnEpoch}

    fi
  fi
fi
