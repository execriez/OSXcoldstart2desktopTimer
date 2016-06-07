#!/bin/bash
#
# Calculates how long it takes to get to a desktop from cold on OSX
# Mark J Swift
GLB_VERSTAG="1.0.7"

# how many iterations we should do
GLB_ITERATIONS=10

# how long we should wait at the desktop before shutting down
GLB_DSKTOPTIME=15

# how many seconds out a timing can be from the average before its discarded
GLB_TIMINGERR=10

# send message to log file and stdout
f_logmessage()   # messagetxt
{
  local LCL_MESSAGETXT

  LCL_MESSAGETXT=${1}

  echo "$(date): ${LCL_MESSAGETXT}" | tee -a "${GLB_MYPATH}"/${GLB_MYNAME}.log >/dev/null
  echo "${LCL_MESSAGETXT}"
}

# Schedule event type at specified time. Identify the event with a unique tag
# waketype can be one of sleep, wake, poweron, shutdown, wakeorpoweron
f_schedule4epoch()   # TAG WAKETYPE EPOCH
{
  local LCL_SCHED_EPOCH
  local LCL_SCHED_LINE
  local LCL_NOW_EPOCH

  LCL_TAG=${1}
  LCL_WAKETYPE=${2}
  LCL_SCHED_EPOCH=${3}

  LCL_NOW_EPOCH=$(date -u "+%s")

  if [ ${LCL_NOW_EPOCH} -lt ${LCL_SCHED_EPOCH} ]
  then
    # check there isnt a named scheduled already
    pmset -g sched | grep -i "${LCL_WAKETYPE}" | grep -i "${LCL_TAG}" | tr -s " " | cut -d " " -f5-6 | while read LCL_SCHED_LINE
    do
      pmset schedule cancel ${LCL_WAKETYPE} "${LCL_SCHED_LINE}" "${LCL_TAG}" 2>/dev/null
    done

    LCL_SCHED_LINE=$(date -r ${LCL_SCHED_EPOCH} "+%m/%d/%y %H:%M:%S")
    pmset schedule ${LCL_WAKETYPE} "${LCL_SCHED_LINE}" "${LCL_TAG}"
  fi
}

# Full souce of this script
GLB_MYSOURCE="${0}"

# Filename of this script
GLB_MYSCRIPT="$(basename "${GLB_MYSOURCE}")"

# Filename without extension
GLB_MYNAME="$(echo "${GLB_MYSCRIPT}" | sed "s/\.[^\.]*$//g")"

# Path to this script
GLB_MYPATH="$(dirname "${GLB_MYSOURCE}")"

# change directory to where this script is running
cd "${GLB_MYPATH}"

# timezone for executing PHP date functions
GLB_TIMEZONE="Europe/London"

# init string for executing PHP commands
GLB_PHPINI=$(php -r 'if (floatval(phpversion()) >= 5.1){echo "date_default_timezone_set(\"'${GLB_TIMEZONE}'\");";}')

# info about this user
GLB_USERNAME=$(whoami)
GLB_USERHOME=$(eval echo ~${GLB_USERNAME})

# info about this workstation
GLB_MODELVERSION=$(sysctl -n hw.model)

GLB_BuildVersionStampAsString="$(sw_vers -buildVersion)"
GLB_SystemVersionStampAsString="$(sw_vers -productVersion)"

if [ $(id -u) -ne 0 ]
then
  if [ ! -e "${GLB_MYPATH}"/${GLB_MYNAME}-timings.txt ]
  then
    f_logmessage "INFO: Installing ${GLB_MYNAME} - ${GLB_VERSTAG}"

    cat << EOF > /tmp/${GLB_MYNAME}-SchedulePowerOn.plist
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>${GLB_MYNAME}-SchedulePowerOn</string>
	<key>ProgramArguments</key>
	<array>
		<string>${GLB_MYSOURCE}</string>
	</array>
	<key>WatchPaths</key>
	<array>
	<string>${GLB_MYPATH}/${GLB_MYNAME}-timings.txt</string>
	</array>
	<key>OnDemand</key>
	<true/>
	<key>UserName</key>
	<string>root</string>
</dict>
</plist>
EOF

    chmod 644 /tmp/${GLB_MYNAME}-SchedulePowerOn.plist

    echo ""
    echo "Enter the password for user '"${GLB_USERNAME}"' (must be an admin user)"
    echo ""

    sudo cp /tmp/${GLB_MYNAME}-SchedulePowerOn.plist /Library/LaunchDaemons/${GLB_MYNAME}-SchedulePowerOn.plist

    # If root LaunchDaemon installed OK, install the user LaunchAgent too
    if [ -e /Library/LaunchDaemons/${GLB_MYNAME}-SchedulePowerOn.plist ]
    then
      # Maybe we should disable Spotlight?
      # sudo touch /.metadata_never_index

      mkdir -p ${GLB_USERHOME}/Library/LaunchAgents

      cat << EOF > ${GLB_USERHOME}/Library/LaunchAgents/${GLB_MYNAME}-timer.plist
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>${GLB_MYNAME}-timer</string>
	<key>ProgramArguments</key>
	<array>
		<string>${GLB_MYSOURCE}</string>
	</array>
	<key>RunAtLoad</key>
	<true/>
</dict>
</plist>
EOF

      # Initialise the timings file
      touch -t 200601010000.00 "${GLB_MYPATH}"/${GLB_MYNAME}-timings.txt

      echo "${GLB_MYNAME} installed OK."
      echo ""
      echo "PLEASE READ CAREFULLY!"
      echo "To begin the timings do the following:"
      echo "1. Quit all running applications"
      echo "2. Close all windows,"
      echo "3. Enable Auto log in for user '"${GLB_USERNAME}"'"
      echo '   (System Preferences>Users & Groups>Login Options>Automatic login)'
      echo "4. Reboot."
      echo ""
      echo "Note: during the timing process, the workstation will power off,"
      echo "      then auto power on ${GLB_ITERATIONS} times before finishing."
      echo ""
      echo "The whole process will probably take between $((${GLB_ITERATIONS}*2)) and $((${GLB_ITERATIONS}*3)) minutes to complete."
      echo ""
      echo "To stop the process prematurely, wait for the workstation to switch off,"
      echo "then immediately switch it on again."
      echo ""
      echo "If this does not work, boot into Single-User mode and delete the"
      echo "following files:"
      echo "  ${GLB_USERHOME}/Library/LaunchAgents/${GLB_MYNAME}-timer.plist"
      echo "  /Library/LaunchDaemons/${GLB_MYNAME}-SchedulePowerOn.plist"
      echo ""

    else
      f_logmessage "INFO: ${GLB_MYNAME} failed to install - everything is as it was."

    fi

  else
    # ~/Library/LaunchAgent - runs as logged in user - activated after login

    GLB_NOW_EPOCH=$(date -u "+%s")
    GLB_COUNT=$(cat "${GLB_MYPATH}"/${GLB_MYNAME}-timings.txt | wc -l)

    # When were we sheduled to power on?
    GLB_LAST_POWERON_EPOCH=$(stat -f "%m" "${GLB_MYPATH}"/${GLB_MYNAME}-timings.txt)

    # How long did it take to start logging after boot?
    GLB_BOOTLOG_TIME=$(sysctl kern.boottime | tr -d "\n" | tr "}" "\n" | tr "=" "\n" | tail -n1)
    GLB_BOOTLOG_EPOCH=$(php -r ${GLB_PHPINI}'echo strtotime("'"${GLB_BOOTLOG_TIME}"'"), "\n";')
    #GLB_BOOTLOG_EPOCH=$(sysctl kern.boottime | sed -E "s|[^{]*{([^}]*).*|\1|" | tr "," "\n" | grep " sec = " | tr -d " " | cut -d "=" -f2)
    if [ -n "${GLB_BOOTLOG_EPOCH}" ]
    then
      GLB_BOOTLOGDELAY=$((${GLB_BOOTLOG_EPOCH}-${GLB_LAST_POWERON_EPOCH}))

      if [ ${GLB_BOOTLOGDELAY} -lt 0 ]
      then
        # we have prematurely switched workstation on in order to stop the timings
        GLB_ITERATIONS=${GLB_COUNT}
      fi
    fi

    # How long did it take to get to a useable desktop?
    GLB_COLDSTART2DESTOP=$((${GLB_NOW_EPOCH}-${GLB_LAST_POWERON_EPOCH}))

    if [ ${GLB_COLDSTART2DESTOP} -lt 0 ]
    then
      # we have prematurely switched workstation on in order to stop the timings
      GLB_ITERATIONS=${GLB_COUNT}
    fi

    if [ ${GLB_COUNT} -lt ${GLB_ITERATIONS} ]
    then
      if [ ${GLB_LAST_POWERON_EPOCH} -eq 1136073600 ]
      then
        # just installed
        f_logmessage "INFO: Begin Timing"

        # trigger root LaunchDAemon
        touch "${GLB_MYPATH}"/${GLB_MYNAME}-timings.txt

      else
        if [ -n "${GLB_BOOTLOGDELAY}" ]
        then
          f_logmessage "INFO: BOOTLOGDELAY ${GLB_BOOTLOGDELAY} seconds."
          echo ${GLB_BOOTLOGDELAY} >> "${GLB_MYPATH}"/${GLB_MYNAME}-bootlogdelay.txt
        fi

        f_logmessage "INFO: COLDSTART2DESTOP ${GLB_COLDSTART2DESTOP} seconds."

        # wait around a bit for things to settle down
        sleep ${GLB_DSKTOPTIME}

        # trigger root LaunchDAemon
        echo ${GLB_COLDSTART2DESTOP} >> "${GLB_MYPATH}"/${GLB_MYNAME}-timings.txt

      fi

      GLB_NOW_EPOCH=$(date -u "+%s")
      # wait until root LaunchDaemon has scheduled a poweron
      while [ $(stat -f "%m" "${GLB_MYPATH}"/${GLB_MYNAME}-timings.txt) -le ${GLB_NOW_EPOCH} ]
      do
        sleep 1
      done

      # applescript code to shut down gracefully
      /usr/bin/osascript -e 'tell application "System Events" to shut down'

    else
      f_logmessage "INFO: Workstation Model ${GLB_MODELVERSION} - OS Version ${GLB_SystemVersionStampAsString} - OS Build ${GLB_BuildVersionStampAsString}"

      # Averages are done two-pass to throw away timings that are much bigger than expected.
      # You could call it cheating - but these timings skew results - and are unexplainable.

      if [ -e "${GLB_MYPATH}"/${GLB_MYNAME}-bootlogdelay.txt ]
      then
        # 1st run - get a close expected average
        GLB_TOTALTIME=0
        GLB_TOTALCOUNT=0
        while read GLB_BOOTLOGDELAY
        do
          GLB_TOTALTIME=$(( ${GLB_TOTALTIME} + ${GLB_BOOTLOGDELAY} ))
          GLB_TOTALCOUNT=$(( ${GLB_TOTALCOUNT} + 1 ))
        done <"${GLB_MYPATH}"/${GLB_MYNAME}-bootlogdelay.txt
        GLB_CLOSEAVGTIME=$(( ${GLB_TOTALTIME} / ${GLB_TOTALCOUNT} ))

        # 2nd run - get an average that doesnt include timings bigger than expected
        GLB_TOTALTIME=0
        GLB_TOTALCOUNT=0
        while read GLB_BOOTLOGDELAY
        do
          if [ $(( (${GLB_BOOTLOGDELAY} - ${GLB_CLOSEAVGTIME}) )) -le ${GLB_TIMINGERR} ]
          then
            f_logmessage "INFO: timing ${GLB_BOOTLOGDELAY} accepted."
            GLB_TOTALTIME=$(( ${GLB_TOTALTIME} + ${GLB_BOOTLOGDELAY} ))
            GLB_TOTALCOUNT=$(( ${GLB_TOTALCOUNT} + 1 ))
          else
            f_logmessage "INFO: timing ${GLB_BOOTLOGDELAY} rejected."
          fi
        done <"${GLB_MYPATH}"/${GLB_MYNAME}-bootlogdelay.txt
        GLB_AVGTIME=$(( ${GLB_TOTALTIME} / ${GLB_TOTALCOUNT} ))

        f_logmessage "INFO: Average BOOTLOGDELAY ${GLB_AVGTIME} seconds, measured over ${GLB_TOTALCOUNT} samples."

        rm -f "${GLB_MYPATH}"/${GLB_MYNAME}-bootlogdelay.txt
      fi

      # 1st run - get a close expected average
      GLB_TOTALTIME=0
      GLB_TOTALCOUNT=0
      while read GLB_COLDSTART2DESTOP
      do
        GLB_TOTALTIME=$(( ${GLB_TOTALTIME} + ${GLB_COLDSTART2DESTOP} ))
        GLB_TOTALCOUNT=$(( ${GLB_TOTALCOUNT} + 1 ))
      done <"${GLB_MYPATH}"/${GLB_MYNAME}-timings.txt
      GLB_CLOSEAVGTIME=$(( ${GLB_TOTALTIME} / ${GLB_TOTALCOUNT} ))

      # 2nd run - get an average that doesnt include timings bigger than expected
      GLB_TOTALTIME=0
      GLB_TOTALCOUNT=0
      while read GLB_COLDSTART2DESTOP
      do
        if [ $(( (${GLB_COLDSTART2DESTOP} - ${GLB_CLOSEAVGTIME}) )) -le ${GLB_TIMINGERR} ]
        then
          f_logmessage "INFO: timing ${GLB_COLDSTART2DESTOP} accepted."
          GLB_TOTALTIME=$(( ${GLB_TOTALTIME} + ${GLB_COLDSTART2DESTOP} ))
          GLB_TOTALCOUNT=$(( ${GLB_TOTALCOUNT} + 1 ))
        else
          f_logmessage "INFO: timing ${GLB_COLDSTART2DESTOP} rejected."
        fi
      done <"${GLB_MYPATH}"/${GLB_MYNAME}-timings.txt
      GLB_AVGTIME=$(( ${GLB_TOTALTIME} / ${GLB_TOTALCOUNT} ))

      f_logmessage "INFO: Average COLDSTART2DESTOP ${GLB_AVGTIME} seconds, measured over ${GLB_TOTALCOUNT} samples."

      # signal root LaunchDaemon to uninstall
      rm -f "${GLB_MYPATH}"/${GLB_MYNAME}-timings.txt

      f_logmessage "INFO: Uninstalling ${GLB_MYNAME} (per-user LaunchAgent)"
      rm -f ${GLB_USERHOME}/Library/LaunchAgents/${GLB_MYNAME}-timer.plist

      # wait until LauncDaemon has uninstalled too
      while [ -e /Library/LaunchDaemons/${GLB_MYNAME}-SchedulePowerOn.plist ]
      do
        sleep 1
      done

      # applescript code to restart gracefully
      /usr/bin/osascript -e 'tell application "System Events" to restart'
    fi

  fi

else
  # Library/LaunchDaemon - runs as root - activated by modifying the xxx-timings.txt file

  if [ ! -e "${GLB_MYPATH}"/${GLB_MYNAME}-timings.txt ]
  then
    # if the watched file no longer exists, uninstall

    f_logmessage "INFO: Uninstalling ${GLB_MYNAME} (system-level LaunchDaemon)"
    rm -f /Library/LaunchDaemons/${GLB_MYNAME}-SchedulePowerOn.plist

  else
    GLB_NOW_EPOCH=$(date -u "+%s")
    GLB_LAST_UPDATE_EPOCH=$(stat -f "%m" "${GLB_MYPATH}"/${GLB_MYNAME}-timings.txt)

    if [ ${GLB_LAST_UPDATE_EPOCH} -le ${GLB_NOW_EPOCH} ]
    then

      # schedule a power on. The user process will then shutdown gracefully.

      # schedule the next power on - so we know exactly when this is to happen
      GLB_NEXT_POWERON_EPOCH=$((${GLB_NOW_EPOCH}+120-(${GLB_NOW_EPOCH} % 60)))

      f_schedule4epoch ${GLB_MYNAME} poweron ${GLB_NEXT_POWERON_EPOCH}

      # make sure we are not held up by a User Agreement
      rm -f /Library/Security/PolicyBanner*

      #touch -t $(date -jf "%s" ${GLB_NEXT_POWERON_EPOCH} "+%Y%m%d%H%M.%S") "${GLB_MYPATH}"/${GLB_MYNAME}-timings.txt
      touch -t $(php -r ${GLB_PHPINI}'echo date("ymdHi.s",'${GLB_NEXT_POWERON_EPOCH}'), "\n";') "${GLB_MYPATH}"/${GLB_MYNAME}-timings.txt

    fi
  fi
fi
