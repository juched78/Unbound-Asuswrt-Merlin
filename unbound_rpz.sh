#!/bin/sh
##
# (        ) (      (                                   
# )\ )  ( /( )\ )   )\ )                         (  (   
#(()/(  )\()|()/(  (()/( (  (     (  (  (      ) )\ )\  
# /(_))((_)\ /(_))  /(_)))\ )(   ))\ )\))(  ( /(((_|(_) 
#(_))_  _((_|_))   (_))_((_|()\ /((_|(_)()\ )(_))_  _   
# |   \| \| / __|  | |_  (_)((_|_)) _(()((_|(_)_| || |  
# | |) | .` \__ \  | __| | | '_/ -_)\ V  V / _` | || |  
# |___/|_|\_|___/  |_|   |_|_| \___| \_/\_/\__,_|_||_|  
## by @juched - DNS Firewall in Unbound (needs unbound 1.10+)
## Unbound-RPZ.sh
## v1.0 - Initial quick release.  Run it once, it keeps running.  No installer.
## v1.0.1 - Only reload if unbound is running
## v1.1.0 - Updated with proper commands to install/uninstall and update.  Now survives reboot of router
## v1.2.0 - Support unbound.conf.firewall generation during install, and clean up during uninstall (needs v3.03 of unbound_manager)
## v1.2.1 - Patch to remove CNAME entires which end in a dot - breakes load of RPZ file
readonly SCRIPT_VERSION="v1.2.1"

#define needed vars
readonly rpzSitesFile="/opt/share/unbound/configs/rpzsites"
readonly SCRIPT_NAME="Unbound_RPZ.sh"
readonly SCRIPT_NAME_LOWER="unbound_rpz.sh"
readonly SCRIPT_DIR="/jffs/addons/unbound"
readonly FIREWALL_CONFIG="/opt/share/unbound/configs/unbound.conf.firewall"

#define needed commands
readonly UNBOUNCTRLCMD="unbound-control"

Say(){
   echo -e $$ $@ | logger -st "($(basename $0))"
}

ScriptHeader() {
	printf "\\n"
	printf "##\\n"
	printf "# (        ) (      (                                   \\n"
	printf "# )\ )  ( /( )\ )   )\ )                         (  (   \\n"
	printf "#(()/(  )\()|()/(  (()/( (  (     (  (  (      ) )\ )\  \\n"
	printf "# /(_))((_)\ /(_))  /(_)))\ )(   ))\ )\))(  ( /(((_|(_) \\n"
	printf "#(_))_  _((_|_))   (_))_((_|()\ /((_|(_)()\ )(_))_  _   \\n"
	printf "# |   \| \| / __|  | |_  (_)((_|_)) _(()((_|(_)_| || |  \\n"
	printf "# | |) | .\` \__ \  | __| | | '_/ -_)\ V  V / _\` | || |  \\n"
	printf "# |___/|_|\_|___/  |_|   |_|_| \___| \_/\_/\__,_|_||_|  \\n"

	printf "## by @juched - DNS Firewall in Unbound (needs unbound 1.10+) - %s\\n" "$SCRIPT_VERSION"
	printf "\\n"
	printf "unbound_rpz.sh\\n"
	printf "		install   - Starts the automatic download of data files\\n"
	printf "		download  - Download and reload the data files used for DNS Firewall\\n"
	printf "		uninstall - Stops the automatic download of data files, and clean up\\n"
}

# $1 rpz_name $2 url $3 filename
generate_rpz() {
  echo "rpz:" >> "$FIREWALL_CONFIG"
  echo "name: $1" >> "$FIREWALL_CONFIG"
  echo "#url: \"$2\"" >> "$FIREWALL_CONFIG"
  echo "zonefile: $3" >> "$FIREWALL_CONFIG"
  echo "rpz-log: yes" >> "$FIREWALL_CONFIG"
  echo "rpz-log-name: \"$1\"" >> "$FIREWALL_CONFIG"
  echo "rpz-action-override: nxdomain" >> "$FIREWALL_CONFIG"
}

download_reload() {
  sitesfile=$1
  cmd=$2
  count=1

  if [ "$cmd" == "install" ]; then
    echo "Creating new unbound.conf.firewall file."
    echo "" > "$FIREWALL_CONFIG"
  fi

  while read -r line
  do
    set -- $line
    #[ "${$line:0:1}" == "#" ] && continue

    if [ "$cmd" != "uninstall" ]; then
      Say "Attempting to Download $count of $(awk 'NF && !/^[:space:]*#/' $sitesfile | wc -l) from $1."
      curl --progress-bar $1 > $2
      dos2unix $2
      sed -i '/\. CNAME \./d' $2
    fi

    if [ "$cmd" == "install" ]; then
      echo "Adding zone $3 to unbound.conf.firewall."
      generate_rpz $3 $1 $2
    fi

    if [ "$cmd" == "uninstall" ]; then
      echo "Removing zone file for zone $3."
      [ -f $2 ] && rm -rf $2
    fi 

    if [ "$cmd" == "reload" ] && [ ! -z "$(pidof unbound)" ]; then
      Say "Reload unbound for zone named $3"
      $UNBOUNCTRLCMD auth_zone_reload "$3"
    fi
    count=$((count + 1))
  done < "$sitesfile"
}

Auto_Startup(){
	case $1 in
		create)
			if [ -f /jffs/scripts/services-start ]; then
				STARTUPLINECOUNTEX=$(grep -cx "$SCRIPT_DIR/$SCRIPT_NAME_LOWER startup"' # '"$SCRIPT_NAME" /jffs/scripts/services-start)
				
				if [ "$STARTUPLINECOUNTEX" -eq 0 ]; then
					echo "$SCRIPT_DIR/$SCRIPT_NAME_LOWER startup"' # '"$SCRIPT_NAME" >> /jffs/scripts/services-start
					echo "Created startup hook in services-start."
				fi
			else
				echo "#!/bin/sh" > /jffs/scripts/services-start
				echo "" >> /jffs/scripts/services-start
				echo "$SCRIPT_DIR/$SCRIPT_NAME_LOWER startup"' # '"$SCRIPT_NAME" >> /jffs/scripts/services-start
				chmod 0755 /jffs/scripts/services-start
				echo "Created startup hook in services-start."
			fi
		;;
		delete)
			if [ -f /jffs/scripts/services-start ]; then
				STARTUPLINECOUNT=$(grep -c '# '"$SCRIPT_NAME" /jffs/scripts/services-start)
				
				if [ "$STARTUPLINECOUNT" -gt 0 ]; then
					sed -i -e '/# '"$SCRIPT_NAME"'/d' /jffs/scripts/services-start
					echo "Removed startup hook in services-start."
				fi
			fi
		;;
	esac
}

Auto_Cron(){
	case $1 in
		create)
			STARTUPLINECOUNT=$(cru l | grep -c "$SCRIPT_NAME")
			
			if [ "$STARTUPLINECOUNT" -eq 0 ]; then
				cru a "$SCRIPT_NAME" "*/15 * * * * $SCRIPT_DIR/$SCRIPT_NAME_LOWER download"
				echo "Created cron job."
			fi
		;;
		delete)
			STARTUPLINECOUNT=$(cru l | grep -c "$SCRIPT_NAME")
			
			if [ "$STARTUPLINECOUNT" -gt 0 ]; then
				cru d "$SCRIPT_NAME"
				echo "Removed cron job."
			fi
		;;
	esac
}


#Main loop
if [ -z "$1" ]; then
	ScriptHeader
	exit 0
fi

case "$1" in
	install)
		Auto_Startup create
		Auto_Cron create
		download_reload "$rpzSitesFile" "install"
		echo "Installed."
		exit 0
	;;
	startup)
		Auto_Cron create
		exit 0
	;;
	download)
		download_reload "$rpzSitesFile" "reload"
		exit 0
	;;
	uninstall)
		Auto_Startup delete
		Auto_Cron delete
		echo "Uninstalled."

		# cleanup zones files previously downloaded
		download_reload "$rpzSitesFile" "uninstall"
		[ -f "$FIREWALL_CONFIG" ] && rm -rf "$FIREWALL_CONFIG"
		exit 0
	;;
esac

