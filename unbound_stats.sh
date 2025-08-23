#!/bin/sh
##
# ____ ___     ___.                            .___   _________ __          __          
#|    |   \____\_ |__   ____  __ __  ____    __| _/  /   _____//  |______ _/  |_  ______
#|    |   /    \| __ \ /  _ \|  |  \/    \  / __ |   \_____  \\   __\__  \\   __\/  ___/
#|    |  /   |  \ \_\ (  <_> )  |  /   |  \/ /_/ |   /        \|  |  / __ \|  |  \___ \ 
#|______/|___|  /___  /\____/|____/|___|  /\____ |  /_______  /|__| (____  /__| /____  >
#             \/    \/                  \/      \/          \/           \/          \/ 
## by @juched - Generate Stats for GUI tab
## with credit to @JackYaz for his shared scripts
##
## https://github.com/juched78/Unbound-Asuswrt-Merlin/
##
#########################################################################################################
## v1.0.0 - initial text based only UI items
## v1.1.0 - March 03 2020 - Added graphs for histogram and answers, fixed install to not create duplicate tabs
## v1.1.1 - March 08 2020 - Added new install of JackYaz shared graphing files (previously needed to have one of JackYaz's other plugins installed)
## v1.1.2 - March 09 2020 - Cleanup .db and .md5 files on uninstall, move startup to post-mount, fixed directory check
## v1.2.0 - March 23 2020 - Add output for top ad blocked graph top 10 and top domains - moved stats DB to USB
## v1.2.1 - March 26 2020 - Added daily replies table
## v1.2.2 - April 05 2020 - Added tracking of client ip
## v1.2.3 - April 10 2020 - Fixed issue with "" domain name in SQL, breaking JS
## v1.2.4 - April 12 2020 - Removed error message on clean install for missing md5 file
## v1.2.5 - April 13 2020 - During install, do not Generate stats if unbound is not running
## v1.3.0 - April 16 2020 - Show stats for DNS Firewall
## v1.4.0 - March 07 2021 - Introduce locking standard around mounting and unmounting, increase max pages to 20
## v1.4.1 - April 06 2021 - Fix startup timeout killing init, (missing tabs, double data, etc).
## v1.4.2 -  July 04 2024 - Fixed errors when loading WebGUI page on 3006.102.1 F/W version [Martinski W.]
##           June 08 2025 - Fixed errors not linking the required shared-jy directory if only Unbound is installed [ExtremeFiretop]
##           June 08 2025 - Updated URL for shared JackYaz chart/graph files to use new AMTM-OSR path [ExtremeFiretop]
##           June 08 2025 - Improved fix to make sure symbolic link to shared directory for JackYaz chart/graph files
##                          gets created under all conditions: installation, startups and reboots [Martinski W.]
##           June 08 2025 - Added "export PATH" statement to give the built-in binaries higher priority than 
##                          their equivalent Entware binaries [Martinski W.]
## v1.4.3 -  June 14 2025 - Added "checkupdate" and "forceupdate" parameters to make it easier to update
##                          the script without forcing users to uninstall and reinstall [Martinski W.]
##           June 14 2025 - Added "help" parameter to show list of available commands [Martinski W.]
##            Aug 11 2025 - Added error checking and handling plus various code improvements.
#########################################################################################################
# Last Modified: 2025-Aug-23
#-------------------------------------------------

############## Shellcheck Directives ##############
# shellcheck disable=SC2016
# shellcheck disable=SC2018
# shellcheck disable=SC2019
# shellcheck disable=SC2059
# shellcheck disable=SC2155
# shellcheck disable=SC2174
# shellcheck disable=SC3018
# shellcheck disable=SC3043
# shellcheck disable=SC3045
###################################################

readonly SCRIPT_VERSION="v1.4.3"
readonly SCRIPT_VERSTAG="25082322"
SCRIPT_BRANCH="develop"
SCRIPT_REPO="https://raw.githubusercontent.com/juched78/Unbound-Asuswrt-Merlin/$SCRIPT_BRANCH"

#define www script names#
readonly SCRIPT_WEBPAGE_DIR="$(readlink -f /www/user)"
readonly SCRIPT_NAME="Unbound_Stats.sh"
readonly LOG_SCRIPT_NAME="Unbound_Log.sh"
readonly SCRIPT_NAME_LOWER="unbound_stats.sh"
readonly LOG_SCRIPT_NAME_LOWER="unbound_log.sh"
readonly SCRIPT_WEB_DIR="$SCRIPT_WEBPAGE_DIR/$SCRIPT_NAME_LOWER"
readonly SCRIPT_DIR="/jffs/addons/unbound"
readonly TEMP_MENU_TREE="/tmp/menuTree.js"

#needed for shared jy graph files from @JackYaz#
readonly SHARED_DIR="/jffs/addons/shared-jy"
readonly SHARED_REPO="https://raw.githubusercontent.com/AMTM-OSR/shared-jy/master"
readonly SHARED_WEB_DIR="$SCRIPT_WEBPAGE_DIR/shared-jy"

#define needed commands#
readonly UNBOUNCTRLCMD="unbound-control"

##-------------------------------------##
## Added by Martinski W. [2025-Jun-13] ##
##-------------------------------------##
readonly scriptVersRegExp="v[0-9]{1,2}([.][0-9]{1,2})([.][0-9]{1,2})"
readonly WEBPAGE_TAG="Unbound"
readonly webPageMenuAddons="menuName: \"Addons\","
readonly webPageHelpSupprt="tabName: \"Help & Support\"},"
readonly webPageFileRegExp="user([1-9]|[1-2][0-9])[.]asp"
readonly webPageLineTabExp="\{url: \"$webPageFileRegExp\", tabName: "
readonly webPageLineRegExp="${webPageLineTabExp}\"$WEBPAGE_TAG\"\},"
readonly BEGIN_MenuAddOnsTag="/\*\*BEGIN:_AddOns_\*\*/"
readonly ENDIN_MenuAddOnsTag="/\*\*ENDIN:_AddOns_\*\*/"
readonly branchx_TAG="Branch: $SCRIPT_BRANCH"
readonly version_TAG="${SCRIPT_VERSION}_${SCRIPT_VERSTAG}"
readonly SHARE_TEMP_DIR="/opt/share/tmp"

readonly CLRct="\e[0m"
readonly CRIT="\e[41m"
readonly ERR="\e[31m"
readonly WARN="\e[33m"
readonly PASS="\e[32m"
readonly BOLD="\e[1m"
readonly INFO="${BOLD}\e[36m"
readonly REDct="\e[1;31m"
readonly GRNct="\e[1;32m"
readonly MGNTct="\e[1;35m"

# Give priority to built-in binaries #
export PATH="/bin:/usr/bin:/sbin:/usr/sbin:$PATH"

#define data file names#
raw_statsFile="/tmp/unbound_raw_stats.txt"
statsFile="$SCRIPT_WEB_DIR/unboundstats.txt"
statsTitleFile="$SCRIPT_WEB_DIR/unboundstatstitle.txt"
statsFileJS="$SCRIPT_WEB_DIR/unboundstats.js"
statsTitleFileJS="$SCRIPT_WEB_DIR/unboundstatstitle.js"
statsCHPFileJS="$SCRIPT_WEB_DIR/unboundchpstats.js"
statsRPZFileJS="$SCRIPT_WEB_DIR/unboundrpzstats.js"
statsRPZHitsFileJS="$SCRIPT_WEB_DIR/unboundrpzhits.js"
statsHistogramFileJS="$SCRIPT_WEB_DIR/unboundhistogramstats.js"
statsAnswersFileJS="$SCRIPT_WEB_DIR/unboundanswersstats.js"
statsTopBlockedFileJS="$SCRIPT_WEB_DIR/unboundtopblockedstats.js"
statsTopRepliesFileJS="$SCRIPT_WEB_DIR/unboundtoprepliesstats.js"
statsDailyRepliesFileJS="$SCRIPT_WEB_DIR/unbounddailyreplies.js"
dailyRepliesCSVFile="$SCRIPT_WEB_DIR/unboundrepliestoday.csv"
adblockStatsFile="/opt/var/lib/unbound/adblock/stats.txt"

#DB files to hold data for uptime graph#
DB_OLD_Stats="$SCRIPT_DIR/unboundstats.db"
ubDBASE_Logs="/opt/var/lib/unbound/unbound_log.db"
ubDBASE_Stats="/opt/var/lib/unbound/unbound_stats.db"

#save md5 of last installed www ASP file so you can find it again later (in case of www ASP update)
installedMD5File="$SCRIPT_DIR/www-installed.md5"

[ -f /opt/bin/sqlite3 ] && SQLITE3_PATH=/opt/bin/sqlite3 || SQLITE3_PATH=/usr/sbin/sqlite3

##-------------------------------------##
## Added by Martinski W. [2025-Aug-11] ##
##-------------------------------------##
# $1 = print to syslog, $2 = message to print, $3 = log level
Print_Output()
{
	local prioStr  prioNum
	if [ $# -gt 2 ] && [ -n "$3" ]
	then prioStr="$3"
	else prioStr="NOTICE"
	fi
	if [ "$1" = "true" ]
	then
		case "$prioStr" in
		    "$CRIT") prioNum=2 ;;
		     "$ERR") prioNum=3 ;;
		    "$WARN") prioNum=4 ;;
		    "$INFO") prioNum=5 ;; #NOTICE#
		    "$PASS") prioNum=6 ;; #INFO#
		          *) prioNum=5 ;; #NOTICE#
		esac
		logger -t "$SCRIPT_NAME" -p $prioNum "$2"
	fi
	printf "${BOLD}${3}${2}${CLRct}\n\n"
}

Clear_Lock()
{
	rm -f "/tmp/${SCRIPT_NAME}.lock" 2>/dev/null
	return 0
}

Check_Lock()
{
	local ageOfLock

	if [ -f "/tmp/${SCRIPT_NAME}.lock" ]
	then
		ageOfLock="$(($(date +'%s') - $(date +'%s' -r "/tmp/${SCRIPT_NAME}.lock")))"
		if [ "$ageOfLock" -gt 600 ]  #10 minutes#
		then
			Print_Output true "Stale lock file found (>600 seconds old) - purging lock" "$ERR"
			kill "$(sed -n '1p' "/tmp/${SCRIPT_NAME}.lock")" >/dev/null 2>&1
			Clear_Lock
			echo "$$" > "/tmp/${SCRIPT_NAME}.lock"
			return 0
		else
			Print_Output true "Lock file found (age: $ageOfLock seconds) - stopping to prevent duplicate runs" "$ERR"
			if [ $# -eq 0 ] || [ -z "$1" ]
			then
				exit 1
			else
				if [ "$1" = "webui" ]
				then
					exit 1
				fi
				return 1
			fi
		fi
	else
		echo "$$" > "/tmp/${SCRIPT_NAME}.lock"
		return 0
	fi
}

PressEnter()
{
	while true
	do
		printf "Press <Enter> key to continue..."
		read -rs key
		case "$key" in
			*) break ;;
		esac
	done
	return 0
}

##-------------------------------------##
## Added by Martinski W. [2025-Aug-11] ##
##-------------------------------------##
CheckFor_UnboundManager()
{
	if [ -s "$SCRIPT_DIR/unbound_manager.sh" ]
	then return 0
	fi
	local exitMsg=""
	if [ $# -gt 0 ] && [ "$1" = "exitMsg" ]
	then exitMsg=" Exiting..."
	fi
	Print_Output true "**ERROR**: Unbound Manager is NOT installed." "$CRIT"
	Print_Output true "Unbound Manager *MUST* be installed first.$exitMsg" "$ERR"
	return 1
}

#function to create JS file with data#
WriteStats_ToJS()
{
	[ -f "$2" ] && rm -f "$2"
	echo "function $3(){" >> "$2"
	html='document.getElementById("'"$4"'").innerHTML="'
	while IFS='' read -r line || [ -n "$line" ]
	do
		html="${html}${line}\\n"
	done < "$1"
	html="$html"'"'
	printf "%s\n}\n" "$html" >> "$2"
}

WriteData_ToJS()
{
	{
	   echo "var $3;"
	   echo "$3 = [];"
	} >> "$2"
	contents="$3"'.unshift( '

	while IFS='' read -r line || [ -n "$line" ]
	do
		if echo "$line" | grep -q "NaN"; then continue; fi
		if [ $# -gt 3 ] && [ "$4" = "date-day" ]
		then
			datapoint="{ x: moment(\"""$(echo "$line" | awk 'BEGIN{FS=","}{ print $1 }' | awk '{$1=$1};1')""\", \"YYYY-MM-DD\"), y: ""$(echo "$line" | awk 'BEGIN{FS=","}{ print $2 }' | awk '{$1=$1};1')"" }"
		else	
			datapoint="{ x: moment.unix(""$(echo "$line" | awk 'BEGIN{FS=","}{ print $1 }' | awk '{$1=$1};1')""), y: ""$(echo "$line" | awk 'BEGIN{FS=","}{ print $2 }' | awk '{$1=$1};1')"" }"
		fi
		contents="$contents""$datapoint"","
	done < "$1"

	contents="$(echo "$contents" | sed 's/.$//')"
	contents="$contents"");"
	printf "%s\n\n" "$contents" >> "$2"
}

#$1=variable name $2=filename $3=rawStatsFile $4=on fields to add#
WriteUnboundStats_ToJS()
{
	outputvar="$1"
	inputfile="$3"
	outputfile="$2"
	shift; shift; shift

	outputlist=""
	for var in "$@"
	do
		item="$(awk -v pat="$var=" 'BEGIN {FS="[= ]"}$0 ~ pat {print $2}' "$inputfile")"
		if [ -z "$outputlist" ]
		then
			outputlist="$item"
		else
			outputlist="${outputlist}, $item"
		fi
	done

	{
	   echo "var $outputvar;"
	   echo "$outputvar = [];"
	   echo "${outputvar}.unshift($outputlist);"
	   echo
	} >> "$outputfile"
}

#$1=variable name $2=filename $3=on fields to add#
WriteUnboundLabels_ToJS()
{
	outputvar="$1"
	outputfile="$2"
	shift; shift

	outputlist=""
	for var in "$@"
	do
		if [ -z "$outputlist" ]
		then
			outputlist=\"$var\"
		else
			outputlist=$outputlist", "\"$var\"
		fi
	done

	{
	   echo "var $outputvar;"
	   echo "$outputvar = [];"
	   echo "${outputvar}.unshift($outputlist);"
	   echo
	} >> "$outputfile"
}

#$1 sql table, $2 label column, $3 count column, $4 limit count, $5 csv file, $6 sql file, $7 where clause if needed
WriteUnboundSqlLog_ToFile()
{
	{
	   echo ".mode csv"
	   echo ".output $5"
	} > "$6"

	if [ $# -lt 7 ] || [ -z "$7" ]
	then
	    echo "SELECT $2, SUM($3) FROM $1 GROUP BY $2 ORDER BY SUM($3) DESC LIMIT $4;" >> "$6"
	else
	    echo "SELECT $2, SUM($3) FROM $1 $7 GROUP BY $2 ORDER BY SUM($3) DESC LIMIT $4;" >> "$6"
	fi
}

#$1=csv file $2=js file $3=varLabel $4=varData#
WriteUnboundCSV_ToJS()
{
	labels="$3"'.unshift( '
	values="$4"'.unshift( '

	while IFS='' read -r line || [ -n "$line" ]
	do
		if echo "$line" | grep -q "NaN"; then continue; fi
		labels="$labels""$(echo "$line" | awk 'BEGIN{FS=","}{ print "\x27" $1 "\x27" }' | awk '{$1=$1};1')"","
		values="$values""$(echo "$line" | awk 'BEGIN{FS=","}{ print $2 }' | awk '{$1=$1};1')"","
	done < "$1"

	labels="$(echo "$labels" | sed 's/.$//')"
	labels="$labels"");"
	values="$(echo "$values" | sed 's/.$//')"
	values="$values"");"

	{
	   echo "var $3;"
	   echo "$3 = [];"
	   printf "%s\r\n\r\n" "$labels"
	   echo "var $4;"
	   echo "$4 = [];"
	   printf "%s\r\n\r\n" "$values"
	} >> "$2"
}

#$1 csv file $2 js file $3 varLabel $4 varData#
WriteUnboundCSV_ToJS_2Labels()
{
	labels="$3"'.unshift( '
	values="$4"'.unshift( '

	while IFS='' read -r line || [ -n "$line" ]
	do
		if echo "$line" | grep -q "NaN"; then continue; fi
		labels="$labels""$(echo "$line" | awk 'BEGIN{FS=","}{ print "\x27" $1 " (" $2 ")\x27" }' | awk '{$1=$1};1')"","
		values="$values""$(echo "$line" | awk 'BEGIN{FS=","}{ print $3 }' | awk '{$1=$1};1')"","
	done < "$1"

	labels="$(echo "$labels" | sed 's/.$//')"
	labels="$labels"");"
	values="$(echo "$values" | sed 's/.$//')"
	values="$values"");"

	{
	   echo "var $3;"
	   echo "$3 = [];"
	   printf "%s\r\n\r\n" "$labels"
	   echo "var $4;"
	   echo "$4 = [];"
	   printf "%s\r\n\r\n" "$values"
	} >> "$2"
}

##----------------------------------------##
## Modified by Martinski W. [2025-Jul-02] ##
##----------------------------------------##
#$1=csv file $2=JS file $3=JS func name $4=html tag#
WriteUnboundCSV_ToJS_Table()
{
	#clean up any null (or "") strings with null string#
	sed -i 's/""/null/g' "$1"

	[ -f "$2" ] && rm -f "$2"
	echo "function $3(){" >> "$2"
	html='document.getElementById("'"$4"'").outerHTML="'
	numLines="$(wc -l < "$1")"
	if [ "$numLines" -lt 1 ]
	then
		html="${html}<tr><td colspan='4' class='nodata'>No data to display</td></tr>"
	else
		html="$html""$(cat "$1" | awk 'BEGIN{FS=","}{ print "<tr><td>" $1 "</td><td>" $2 "</td><td>"$3 "</td><td>" $4 "</td></tr> \\" }' | awk '{$1=$1};1')"
		html="${html%?}"
	fi
	html="$html"'"'
	printf "%s\n}\n" "$html" >> "$2"
} 

#$1 fieldname $2 tablename $3 frequency (hours) $4 length (days) $5 outputfile $6 sqlfile
WriteSql_ToFile()
{
	{
	   echo ".mode csv"
	   echo ".output $5"
	} >> "$6"
	COUNTER=0
	timenow="$(date '+%s')"
	until [ "$COUNTER" -gt "$((24*$4/$3))" ]
	do
		echo "select $timenow - ((60*60*$3)*($COUNTER)),IFNULL(avg([$1]),'NaN') from $2 WHERE ([Timestamp] >= $timenow - ((60*60*$3)*($COUNTER+1))) AND ([Timestamp] <= $timenow - ((60*60*$3)*$COUNTER));" >> "$6"
		COUNTER="$((COUNTER + 1))"
	done
}

##----------------------------------------##
## Modified by Martinski W. [2025-Aug-11] ##
##----------------------------------------##
Generate_UnboundStats()
{
	#generate stats to raw file#
	if [ -n "$(pidof unbound)" ]
	then 
		printf "$($UNBOUNCTRLCMD stats_noreset)" > "$raw_statsFile"
	else
		#output empty data, cannot get new stats#
		cat /jffs/addons/unbound/emptystats > "$raw_statsFile"
		mkdir -m 775 -p /opt/var/lib/unbound
	fi

	Auto_Startup create 2>/dev/null
	Auto_ServiceEvent create 2>/dev/null
	Auto_Cron create 2>/dev/null

	TZ="$(cat /etc/TZ)"
	export TZ

	LINE=" --------------------------------------------------------"

	#output text stats for box#
	UNB_NUM_Q="$(awk 'BEGIN {FS="[= ]"} /total.num.queries=/ {print $2}' "$raw_statsFile" )"
	UNB_NUM_CH="$(awk 'BEGIN {FS="[= ]"} /total.num.cachehits=/ {print $2}' "$raw_statsFile" )"

	{
	   printf "\n Standard Statistics [%s]\n${LINE}\n" "$(date +'%c')"
	   printf "\n Number of DNS queries: %s" "$UNB_NUM_Q"
	   printf "\n Number of queries that were successfully answered using cache lookup (ie. cache hit): %s" "$UNB_NUM_CH"
	   printf "$(awk 'BEGIN {FS="[= ]"} /total.num.cachemiss=/ {print "\\n Number of queries that needed recursive lookup (ie. cache miss): " $2}' "$raw_statsFile" )"
	   printf "$(awk 'BEGIN {FS="[= ]"} /total.num.zero_ttl=/ {print "\\n Number of replies that were served by an expired cache entry: " $2}' "$raw_statsFile" )"
	   printf "$(awk 'BEGIN {FS="[= ]"} /total.requestlist.exceeded=/ {print "\\n Number of queries dropped because request list was full: " $2}' "$raw_statsFile" )"
	   printf "$(awk 'BEGIN {FS="[= ]"} /total.requestlist.avg=/ {print "\\n Average number of requests in list for recursive processing: " $2}' "$raw_statsFile" )"
	} > "$statsFile"

	#extended stats#
	if [ -n "$(pidof unbound)" ] && \
	   [ "$($UNBOUNCTRLCMD get_option extended-statistics)" = "yes" ]
	then
		{
		   printf "\n\n Extended Statistics\n${LINE}\n"
		   printf "$(awk 'BEGIN {FS="[= ]"} /mem.cache.rrset=/ {print "\\n RRset cache usage in bytes: " $2}' "$raw_statsFile" )"
		   printf "$(awk 'BEGIN {FS="[= ]"} /mem.cache.message=/ {print "\\n Message cache usage in bytes: " $2}' "$raw_statsFile" )"
		} >> "$statsFile"
 	fi

	#adblock stats#
	if [ -f /opt/var/lib/unbound/adblock/adservers ] && [ -f "$adblockStatsFile" ]
	then
		printf "\n\n Adblock Statistics\n${LINE}\n" >> "$statsFile"
		printf "$(cat "$adblockStatsFile")" >> "$statsFile"
	fi

	#calc % served by cache#
	if [ -n "$UNB_NUM_Q" ] && [ "$UNB_NUM_Q" -ne 0 ]
	then
		UNB_CHP="$(awk 'BEGIN {printf "%0.2f", '$UNB_NUM_CH'*100/'$UNB_NUM_Q'}' )"
	else
		UNB_CHP=0
	fi
	echo "Calculated Cache Hit Percentage: $UNB_CHP"
	printf "$(awk 'BEGIN {printf "\n\n Cache hit success percent: %s", '$UNB_CHP'}' )" >> "$statsFile"

	if [ -z "$(pidof unbound)" ]
	then
		printf "\n\n${LINE}\n **WARNING**: Unbound service is NOT found running.\n${LINE}\n" >> "$statsFile"
	fi

	#create JS file to be loaded by web page#
	WriteStats_ToJS "$statsFile" "$statsFileJS" "SetUnboundStats" "unboundstats"

	echo "Unbound Stats generated on $(date +'%c')" > "$statsTitleFile"
	WriteStats_ToJS "$statsTitleFile" "$statsTitleFileJS" "SetUnboundStatsTitle" "unboundstatstitle"

	#use SQLite to track % for graph#
	echo "Adding new value to DB..."
	{
		echo "CREATE TABLE IF NOT EXISTS [unboundstats] ([StatID] INTEGER PRIMARY KEY NOT NULL, [Timestamp] NUMERIC NOT NULL, [CacheHitPercent] REAL NOT NULL);"
		echo "INSERT INTO unboundstats ([Timestamp],[CacheHitPercent]) values($(date '+%s'),$UNB_CHP);"
	} > /tmp/unbound-stats.sql
	"$SQLITE3_PATH" "$ubDBASE_Stats" < /tmp/unbound-stats.sql

	echo "Calculating Daily data..."
	{
		echo ".mode csv"
		echo ".output /tmp/unbound-chp-daily.csv"
		echo "select [Timestamp],[CacheHitPercent] from unboundstats WHERE [Timestamp] >= (strftime('%s','now') - 86400);"
	} > /tmp/unbound-stats.sql
	"$SQLITE3_PATH" "$ubDBASE_Stats" < /tmp/unbound-stats.sql
	rm -f /tmp/unbound-stats.sql

	echo "Calculating Weekly and Monthly data..."
	WriteSql_ToFile "CacheHitPercent" "unboundstats" 1 7 "/tmp/unbound-chp-weekly.csv" "/tmp/unbound-stats.sql"
	WriteSql_ToFile "CacheHitPercent" "unboundstats" 3 30 "/tmp/unbound-chp-monthly.csv" "/tmp/unbound-stats.sql"
	"$SQLITE3_PATH" "$ubDBASE_Stats" < /tmp/unbound-stats.sql

	[ -f "$statsCHPFileJS" ] && rm -f "$statsCHPFileJS"
	WriteData_ToJS "/tmp/unbound-chp-daily.csv" "$statsCHPFileJS" "DatadivLineChartCacheHitPercentDaily"
	WriteData_ToJS "/tmp/unbound-chp-weekly.csv" "$statsCHPFileJS" "DatadivLineChartCacheHitPercentWeekly"
	WriteData_ToJS "/tmp/unbound-chp-monthly.csv" "$statsCHPFileJS" "DatadivLineChartCacheHitPercentMonthly"

	#generate data for histogram on performance#
	echo "Outputting histogram performance data..."
	[ -f "$statsHistogramFileJS" ] && rm -f "$statsHistogramFileJS"

	WriteUnboundStats_ToJS "barDataHistogram" "$statsHistogramFileJS" "$raw_statsFile" "histogram.000000.000000.to.000000.000001" "histogram.000000.000001.to.000000.000002" "histogram.000000.000002.to.000000.000004" "histogram.000000.000004.to.000000.000008" "histogram.000000.000008.to.000000.000016" "histogram.000000.000016.to.000000.000032" "histogram.000000.000032.to.000000.000064" "histogram.000000.000064.to.000000.000128" "histogram.000000.000128.to.000000.000256" "histogram.000000.000256.to.000000.000512" "histogram.000000.000512.to.000000.001024" "histogram.000000.001024.to.000000.002048" "histogram.000000.002048.to.000000.004096" "histogram.000000.004096.to.000000.008192" "histogram.000000.008192.to.000000.016384" "histogram.000000.016384.to.000000.032768" "histogram.000000.032768.to.000000.065536" "histogram.000000.065536.to.000000.131072" "histogram.000000.131072.to.000000.262144" "histogram.000000.262144.to.000000.524288" "histogram.000000.524288.to.000001.000000" "histogram.000001.000000.to.000002.000000" "histogram.000002.000000.to.000004.000000" "histogram.000004.000000.to.000008.000000" "histogram.000008.000000.to.000016.000000" "histogram.000016.000000.to.000032.000000" "histogram.000032.000000.to.000064.000000" "histogram.000064.000000.to.000128.000000" "histogram.000128.000000.to.000256.000000" "histogram.000256.000000.to.000512.000000" "histogram.000512.000000.to.001024.000000" "histogram.001024.000000.to.002048.000000" "histogram.002048.000000.to.004096.000000" "histogram.004096.000000.to.008192.000000" "histogram.008192.000000.to.016384.000000" "histogram.016384.000000.to.032768.000000" "histogram.032768.000000.to.065536.000000" "histogram.065536.000000.to.131072.000000" "histogram.131072.000000.to.262144.000000" "histogram.262144.000000.to.524288.000000"

	WriteUnboundLabels_ToJS "barLabelsHistogram" "$statsHistogramFileJS" "0us - 1us" "1us - 2us" "2us - 4us" "4us - 8us" "8us - 16us" "16us - 32us" "32us - 64us" "64us - 128us" "128us - 256us" "256us - 512us" "512us - 1ms" "1ms - 2ms" "2ms - 4ms" "4ms - 8ms" "8ms - 16ms" "16ms - 32ms" "32ms - 65ms" "65ms - 131ms" "131ms - 262ms" "262ms - 524ms" "524ms - 1s" "1s - 2s" "2s - 4s" "4s - 8s" "8s - 16s" "16s - 32s" "32s - 1m" "1m - 2m" "2m - 4m" "4m - 8.5m" "8.5m - 17m" "17m - 34m" "34m - 1h" "1h - 2.3h" "2.3h - 4.5h" "4.5h - 9.1h" "9.1h - 18.2h" "18.2h - 36.4h" "36.4h - 72.6h" "72.8h - 145.6h"

	#generate data for answers#
	echo "Outputting answers data..."
	[ -f "$statsAnswersFileJS" ] && rm -f "$statsAnswersFileJS"

	WriteUnboundStats_ToJS "barDataAnswers" "$statsAnswersFileJS" "$raw_statsFile" "num.answer.rcode.NOERROR" "num.answer.rcode.FORMERR" "num.answer.rcode.SERVFAIL" "num.answer.rcode.NXDOMAIN" "num.answer.rcode.NOTIMPL" "num.answer.rcode.REFUSED"

	WriteUnboundLabels_ToJS "barLabelsAnswers" "$statsAnswersFileJS" "DNS Query completed successfully" "DNS Query Format Error" "Server failed to complete the DNS request" "Domain name does not exist  (including adblock if enabled)" "Function not implemented" "The server refused to answer for the query"

	#generate data for top blocked domains#
	echo "Outputting top blocked domains..."
	[ -f "$statsTopBlockedFileJS" ] && rm -f "$statsTopBlockedFileJS"
	WriteUnboundSqlLog_ToFile "nx_domains" "domain" "count" "15" "/tmp/unbound-tbd.csv" "/tmp/unbound-tbd.sql"
	"$SQLITE3_PATH" "$ubDBASE_Logs" < /tmp/unbound-tbd.sql

	WriteUnboundCSV_ToJS "/tmp/unbound-tbd.csv" "$statsTopBlockedFileJS" "barLabelsTopBlocked" "barDataTopBlocked"

	#generate data for top 10 weekly replies from unbound#
	echo "Outputting top replies ..."
	[ -f "$statsTopRepliesFileJS" ] && rm -f "$statsTopRepliesFileJS"

	WriteUnboundSqlLog_ToFile "reply_domains" "domain, reply" "count" "15" "/tmp/unbound-topreplies.csv" "/tmp/unbound-topreplies.sql"
	"$SQLITE3_PATH" "$ubDBASE_Logs" < /tmp/unbound-topreplies.sql

	WriteUnboundCSV_ToJS_2Labels "/tmp/unbound-topreplies.csv" "$statsTopRepliesFileJS" "barLabelsTopReplies" "barDataTopReplies"

	#generate daily replies CSV#
	echo "Outputting daily replies ..."
	[ -f "$statsDailyRepliesFileJS" ] && rm -f "$statsDailyRepliesFileJS"

	whereString="WHERE date='""$(date '+%F')""'"
	WriteUnboundSqlLog_ToFile "reply_domains" "domain, client_ip, reply" "count" "250" "/tmp/unbound-dailyreplies.csv" "/tmp/unbound-dailyreplies.sql" "$whereString"
	"$SQLITE3_PATH" "$ubDBASE_Logs" < /tmp/unbound-dailyreplies.sql

	dos2unix "/tmp/unbound-dailyreplies.csv"
	WriteUnboundCSV_ToJS_Table "/tmp/unbound-dailyreplies.csv" "$statsDailyRepliesFileJS" "LoadDailyRepliesTable" "DatadivTableDailyReplies"

	#generate DNS Firewall Events (RPZ)#
	echo "Calculating DNS Firewall data..."
	{
		echo ".mode csv"
		echo ".output /tmp/unbound-rpz-monthly.csv"
		echo "select [date],SUM(count) from rpz_events GROUP BY date ORDER BY date;"
	} > /tmp/unbound-rpz.sql
	"$SQLITE3_PATH" "$ubDBASE_Logs" < /tmp/unbound-rpz.sql

	[ -f "$statsRPZFileJS" ] && rm -f "$statsRPZFileJS"
	WriteData_ToJS "/tmp/unbound-rpz-monthly.csv" "$statsRPZFileJS" "DatadivLineChartRPZHitsMonthly" "date-day"

	#generate table data for all known RPZ hits#
	echo "Outputting DNS Firewall Hits ..."
	[ -f "$statsRPZHitsFileJS" ] && rm -f "$statsRPZHitsFileJS"

	whereString=""
	WriteUnboundSqlLog_ToFile "rpz_events" "domain, client_ip, zone" "count" "250" "/tmp/unbound-rpzhits.csv" "/tmp/unbound-rpzhits.sql" "$whereString"
	"$SQLITE3_PATH" "$ubDBASE_Logs" < /tmp/unbound-rpzhits.sql

	dos2unix "/tmp/unbound-rpzhits.csv"
	WriteUnboundCSV_ToJS_Table "/tmp/unbound-rpzhits.csv" "$statsRPZHitsFileJS" "LoadRPZHitsTable" "DatadivTableRPZHits"

	#cleanup temp files#
	rm -f "/tmp/unbound-"*".csv"
	rm -f "/tmp/unbound-"*".sql"
	[ -f "$raw_statsFile" ] && rm -f "$raw_statsFile"
	[ -f "$statsFile" ] && rm -f "$statsFile"
	[ -f "$statsTitleFile" ] && rm -f "$statsTitleFile"
}

##----------------------------------------##
## Modified by Martinski W. [2025-Jun-30] ##
##----------------------------------------##
Auto_Startup()
{
	local theScriptFilePath="$SCRIPT_DIR/$SCRIPT_NAME_LOWER"
	case $1 in
		create)
			if [ -f /jffs/scripts/post-mount ]
			then
				STARTUPLINECOUNT="$(grep -c '# '"$SCRIPT_NAME" /jffs/scripts/post-mount)"
				STARTUPLINECOUNTEX="$(grep -cx '\[ -x "${1}/entware/bin/opkg" \] && \[ -x '"$theScriptFilePath"' \] && '"$theScriptFilePath"' startup "$@" & # '"$SCRIPT_NAME" /jffs/scripts/post-mount)"

				if [ "$STARTUPLINECOUNT" -gt 1 ] || { [ "$STARTUPLINECOUNTEX" -eq 0 ] && [ "$STARTUPLINECOUNT" -gt 0 ] ; }
				then
					sed -i -e '/# '"$SCRIPT_NAME"'/d' /jffs/scripts/post-mount
					STARTUPLINECOUNTEX=0
				fi
				if [ "$STARTUPLINECOUNTEX" -eq 0 ]
				then
					{
					   echo '[ -x "${1}/entware/bin/opkg" ] && [ -x '"$theScriptFilePath"' ] && '"$theScriptFilePath"' startup "$@" & # '"$SCRIPT_NAME"
					} >> /jffs/scripts/post-mount
				fi
			else
				{
				   echo "#!/bin/sh" ; echo
				   echo '[ -x "${1}/entware/bin/opkg" ] && [ -x '"$theScriptFilePath"' ] && '"$theScriptFilePath"' startup "$@" & # '"$SCRIPT_NAME"
				   echo
				} > /jffs/scripts/post-mount
				chmod 0755 /jffs/scripts/post-mount
			fi
		;;
		delete)
			if [ -f /jffs/scripts/post-mount ]
			then
				STARTUPLINECOUNT="$(grep -c '# '"$SCRIPT_NAME" /jffs/scripts/post-mount)"
				if [ "$STARTUPLINECOUNT" -gt 0 ]; then
					sed -i -e '/# '"$SCRIPT_NAME"'/d' /jffs/scripts/post-mount
				fi
			fi
		;;
	esac
}

##----------------------------------------##
## Modified by Martinski W. [2025-Jun-30] ##
##----------------------------------------##
Auto_ServiceEvent()
{
	local theScriptFilePath="$SCRIPT_DIR/$SCRIPT_NAME_LOWER"
	case $1 in
		create)
			if [ -f /jffs/scripts/service-event ]
			then
				STARTUPLINECOUNT="$(grep -c '# '"$SCRIPT_NAME" /jffs/scripts/service-event)"
				STARTUPLINECOUNTEX="$(grep -cx 'if echo "$2" | /bin/grep -q "'"$SCRIPT_NAME_LOWER"'"; then { '"$theScriptFilePath"' service_event "$@" & }; fi # '"$SCRIPT_NAME" /jffs/scripts/service-event)"

				if [ "$STARTUPLINECOUNT" -gt 1 ] || { [ "$STARTUPLINECOUNTEX" -eq 0 ] && [ "$STARTUPLINECOUNT" -gt 0 ] ; }
				then
					sed -i -e '/# '"$SCRIPT_NAME"'/d' /jffs/scripts/service-event
				fi
				if [ "$STARTUPLINECOUNTEX" -eq 0 ]
				then
					{
					   echo 'if echo "$2" | /bin/grep -q "'"$SCRIPT_NAME_LOWER"'"; then { '"$theScriptFilePath"' service_event "$@" & }; fi # '"$SCRIPT_NAME"
					} >> /jffs/scripts/service-event
				fi
			else
				{
				   echo "#!/bin/sh" ; echo
				   echo 'if echo "$2" | /bin/grep -q "'"$SCRIPT_NAME_LOWER"'"; then { '"$theScriptFilePath"' service_event "$@" & }; fi # '"$SCRIPT_NAME"
				   echo
				} > /jffs/scripts/service-event
				chmod 0755 /jffs/scripts/service-event
			fi
		;;
		delete)
			if [ -f /jffs/scripts/service-event ]
			then
				STARTUPLINECOUNT="$(grep -c '# '"$SCRIPT_NAME" /jffs/scripts/service-event)"
				if [ "$STARTUPLINECOUNT" -gt 0 ]; then
					sed -i -e '/# '"$SCRIPT_NAME"'/d' /jffs/scripts/service-event
				fi
			fi
		;;
	esac
}

Auto_Cron()
{
	case $1 in
		create)
			STARTUPLINECOUNT="$(cru l | grep -c "$SCRIPT_NAME")"
			if [ "$STARTUPLINECOUNT" -eq 0 ]; then
				cru a "$SCRIPT_NAME" "59 * * * * $SCRIPT_DIR/$SCRIPT_NAME_LOWER generate"
			fi

			STARTUPLINECOUNT="$(cru l | grep -c "$LOG_SCRIPT_NAME")"
			if [ "$STARTUPLINECOUNT" -eq 0 ]; then
				cru a "$LOG_SCRIPT_NAME" "57 * * * * $SCRIPT_DIR/$LOG_SCRIPT_NAME_LOWER"
			fi
		;;
		delete)
			STARTUPLINECOUNT="$(cru l | grep -c "$SCRIPT_NAME")"
			if [ "$STARTUPLINECOUNT" -gt 0 ]; then
				cru d "$SCRIPT_NAME"
			fi

			STARTUPLINECOUNT="$(cru l | grep -c "$LOG_SCRIPT_NAME")"
			if [ "$STARTUPLINECOUNT" -gt 0 ]; then
				cru d "$LOG_SCRIPT_NAME"
			fi
		;;
	esac
}

##----------------------------------------##
## Modified by Martinski W. [2025-Jun-28] ##
##----------------------------------------##
Create_Dirs()
{
	if [ ! -d "$SCRIPT_DIR" ]; then
		mkdir -p "$SCRIPT_DIR"
	fi

	if [ ! -d "$SHARED_DIR" ]; then
		mkdir -p "$SHARED_DIR"
	fi

	if [ ! -d "$SCRIPT_WEBPAGE_DIR" ]; then
		mkdir -p "$SCRIPT_WEBPAGE_DIR"
	fi

	if [ ! -d "$SCRIPT_WEB_DIR" ]; then
		mkdir -p "$SCRIPT_WEB_DIR"
	fi

	if [ ! -d "$SHARE_TEMP_DIR" ]
	then
		mkdir -m 777 -p "$SHARE_TEMP_DIR"
		export SQLITE_TMPDIR TMPDIR
	fi

	# Migrate to USB drive to avoid using space on JFFS #
	if [ -f "$DB_OLD_Stats" ]; then
		mv -f "$DB_OLD_Stats" "$ubDBASE_Stats"
	fi
}

##-------------------------------------##
## Added by Martinski W. [2025-Jun-08] ##
##-------------------------------------##
Create_Symlinks()
{
	if [ ! -d "$SHARED_WEB_DIR" ]; then
		ln -s "$SHARED_DIR" "$SHARED_WEB_DIR" 2>/dev/null
	fi
}

Get_WebUI_MD5_Installed() 
{
	md5_installed=0
	if [ -f "$installedMD5File" ]; then
		md5_installed="$(cat "$installedMD5File")"
	fi
}

##-------------------------------------##
## Added by Martinski W. [2025-Jun-28] ##
##-------------------------------------##
_Check_WebGUI_Page_Exists_()
{
   local webPageStr  webPageFile  theWebPage

   if [ ! -f "$TEMP_MENU_TREE" ]
   then echo "NONE" ; return 1 ; fi

   theWebPage="NONE"
   webPageStr="$(grep -E -m1 "^$webPageLineRegExp" "$TEMP_MENU_TREE")"
   if [ -n "$webPageStr" ]
   then
       webPageFile="$(echo "$webPageStr" | grep -owE "$webPageFileRegExp" | head -n1)"
       if [ -n "$webPageFile" ] && [ -s "${SCRIPT_WEBPAGE_DIR}/$webPageFile" ]
       then theWebPage="$webPageFile" ; fi
   fi
   echo "$theWebPage"
}

##----------------------------------------##
## Modified by Martinski W. [2025-Jun-28] ##
##----------------------------------------##
Get_WebUI_Page()
{
	if [ $# -eq 0 ] || [ -z "$1" ] || [ ! -s "$1" ]
	then MyWebPage="NONE" ; return 1 ; fi

	local webPageFile  webPagePath

	MyWebPage="$(_Check_WebGUI_Page_Exists_)"

	for indx in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20
	do
		webPageFile="user${indx}.asp"
		webPagePath="${SCRIPT_WEBPAGE_DIR}/$webPageFile"

		if [ -s "$webPagePath" ] && \
		   { [ "$2" = "$(md5sum < "$webPagePath")" ] || \
		     [ "$(md5sum < "$1")" = "$(md5sum < "$webPagePath")" ] ; }
		then
			MyWebPage="$webPageFile"
			break
		elif [ "$MyWebPage" = "NONE" ] && [ ! -s "$webPagePath" ]
		then
			MyWebPage="$webPageFile"
		fi
	done
}

##----------------------------------------##
## Modified by Martinski W. [2025-Jun-28] ##
##----------------------------------------##
Get_WebUI_URL()
{
	local urlPage  urlProto  urlDomain  urlPort  lanPort

	if [ ! -f "$TEMP_MENU_TREE" ]
	then
		echo "**ERROR**: WebUI page is NOT mounted"
		return 1
	fi

	urlPage="$(sed -nE "/$WEBPAGE_TAG/ s/.*url\: \"(user[0-9]+\.asp)\".*/\1/p" "$TEMP_MENU_TREE")"

	if [ "$(nvram get http_enable)" -eq 1 ]; then
		urlProto="https"
	else
		urlProto="http"
	fi
	if [ -n "$(nvram get lan_domain)" ]; then
		urlDomain="$(nvram get lan_hostname).$(nvram get lan_domain)"
	else
		urlDomain="$(nvram get lan_ipaddr)"
	fi

	lanPort="$(nvram get ${urlProto}_lanport)"
	if [ "$lanPort" -eq 80 ] || [ "$lanPort" -eq 443 ]
	then
		urlPort=""
	else
		urlPort=":$lanPort"
	fi

	if echo "$urlPage" | grep -qE "^${webPageFileRegExp}$" && \
	   [ -s "${SCRIPT_WEBPAGE_DIR}/$urlPage" ]
	then
		echo "${urlProto}://${urlDomain}${urlPort}/${urlPage}" | tr "A-Z" "a-z"
	else
		echo "**ERROR**: WebUI page is NOT found"
	fi
}

##-------------------------------------##
## Added by Martinski W. [2025-Jun-28] ##
##-------------------------------------##
_CreateMenuAddOnsSection_()
{
   if grep -qE "^${webPageMenuAddons}$" "$TEMP_MENU_TREE" && \
      grep -qE "${webPageHelpSupprt}$" "$TEMP_MENU_TREE"
   then return 0 ; fi

   lineinsBefore="$(($(grep -n "^exclude:" "$TEMP_MENU_TREE" | cut -f1 -d':') - 1))"

   sed -i "$lineinsBefore""i\
${BEGIN_MenuAddOnsTag}\n\
,\n{\n\
${webPageMenuAddons}\n\
index: \"menu_Addons\",\n\
tab: [\n\
{url: \"javascript:var helpwindow=window.open('\/ext\/shared-jy\/redirect.htm')\", ${webPageHelpSupprt}\n\
{url: \"NULL\", tabName: \"__INHERIT__\"}\n\
]\n}\n\
${ENDIN_MenuAddOnsTag}" "$TEMP_MENU_TREE"
}

### locking mechanism code credit to Martineau (@MartineauUK) ###
##----------------------------------------##
## Modified by Martinski W. [2025-Aug-11] ##
##----------------------------------------##
Mount_WebUI()
{
	Print_Output true "Mounting WebUI tab for $SCRIPT_NAME" "$PASS"

	LOCKFILE=/tmp/addonwebui.lock
	FD=386
	eval exec "$FD>$LOCKFILE"
	flock -x "$FD"

	Get_WebUI_MD5_Installed
	Get_WebUI_Page "$SCRIPT_DIR/unboundstats_www.asp" "$md5_installed"
	if [ "$MyWebPage" = "NONE" ]
	then
		Print_Output true "**ERROR**: Unable to mount $SCRIPT_NAME WebUI page." "$CRIT"
		flock -u "$FD"		
		exit 1
	fi
	cp -fp "$SCRIPT_DIR/unboundstats_www.asp" "$SCRIPT_WEBPAGE_DIR/$MyWebPage"

	echo "Saving MD5 of installed file $SCRIPT_DIR/unboundstats_www.asp to $installedMD5File"
	md5sum < "$SCRIPT_DIR/unboundstats_www.asp" > "$installedMD5File"

	if [ ! -f /tmp/index_style.css ]; then
		cp -fp /www/index_style.css /tmp/
	fi

	if ! grep -q '.menu_Addons' /tmp/index_style.css
	then
		echo ".menu_Addons { background: url(ext/shared-jy/addons.png); }" >> /tmp/index_style.css
	fi

	umount /www/index_style.css 2>/dev/null
	mount -o bind /tmp/index_style.css /www/index_style.css

	if [ ! -f "$TEMP_MENU_TREE" ]; then
		cp -fp /www/require/modules/menuTree.js "$TEMP_MENU_TREE"
	fi
	sed -i "\\~$MyWebPage~d" "$TEMP_MENU_TREE"

	_CreateMenuAddOnsSection_

	sed -i "/url: \"javascript:var helpwindow=window.open('\/ext\/shared-jy\/redirect.htm'/i {url: \"$MyWebPage\", tabName: \"$WEBPAGE_TAG\"}," "$TEMP_MENU_TREE"

	umount /www/require/modules/menuTree.js 2>/dev/null
	mount -o bind "$TEMP_MENU_TREE" /www/require/modules/menuTree.js

	flock -u "$FD"
	Print_Output true "Mounted $SCRIPT_NAME WebUI page as $MyWebPage" "$PASS"
}

##-------------------------------------##
## Added by Martinski W. [2025-Jun-28] ##
##-------------------------------------##
_RemoveMenuAddOnsSection_()
{
   if [ $# -lt 2 ] || [ -z "$1" ] || [ -z "$2" ] || \
      ! echo "$1" | grep -qE "^[1-9][0-9]*$" || \
      ! echo "$2" | grep -qE "^[1-9][0-9]*$" || \
      [ "$1" -ge "$2" ]
   then return 1 ; fi
   local BEGINnum="$1"  ENDINnum="$2"

   if [ -n "$(sed -E "${BEGINnum},${ENDINnum}!d;/${webPageLineTabExp}/!d" "$TEMP_MENU_TREE")" ]
   then return 1
   fi
   sed -i "${BEGINnum},${ENDINnum}d" "$TEMP_MENU_TREE"
   return 0
}

##-------------------------------------##
## Added by Martinski W. [2025-Jun-28] ##
##-------------------------------------##
_FindandRemoveMenuAddOnsSection_()
{
   local BEGINnum  ENDINnum  retCode=1

   if grep -qE "^${BEGIN_MenuAddOnsTag}$" "$TEMP_MENU_TREE" && \
      grep -qE "^${ENDIN_MenuAddOnsTag}$" "$TEMP_MENU_TREE"
   then
       BEGINnum="$(grep -nE "^${BEGIN_MenuAddOnsTag}$" "$TEMP_MENU_TREE" | awk -F ':' '{print $1}')"
       ENDINnum="$(grep -nE "^${ENDIN_MenuAddOnsTag}$" "$TEMP_MENU_TREE" | awk -F ':' '{print $1}')"
       _RemoveMenuAddOnsSection_ "$BEGINnum" "$ENDINnum" && retCode=0
   fi

   if grep -qE "^${webPageMenuAddons}$" "$TEMP_MENU_TREE" && \
      grep -qE "${webPageHelpSupprt}$" "$TEMP_MENU_TREE"
   then
       BEGINnum="$(grep -nE "^${webPageMenuAddons}$" "$TEMP_MENU_TREE" | awk -F ':' '{print $1}')"
       ENDINnum="$(grep -nE "${webPageHelpSupprt}$" "$TEMP_MENU_TREE" | awk -F ':' '{print $1}')"
       if [ -n "$BEGINnum" ] && [ -n "$ENDINnum" ] && [ "$BEGINnum" -lt "$ENDINnum" ]
       then
           BEGINnum="$((BEGINnum - 2))" ; ENDINnum="$((ENDINnum + 3))"
           if [ "$(sed -n "${BEGINnum}p" "$TEMP_MENU_TREE")" = "," ] && \
              [ "$(sed -n "${ENDINnum}p" "$TEMP_MENU_TREE")" = "}" ]
           then
               _RemoveMenuAddOnsSection_ "$BEGINnum" "$ENDINnum" && retCode=0
           fi
       fi
   fi
   return "$retCode"
}

### locking mechanism code credit to Martineau (@MartineauUK) ###
##----------------------------------------##
## Modified by Martinski W. [2025-Jun-28] ##
##----------------------------------------##
Unmount_WebUI()
{
	LOCKFILE=/tmp/addonwebui.lock
	FD=386
	eval exec "$FD>$LOCKFILE"
	flock -x "$FD"

	Get_WebUI_MD5_Installed
	Get_WebUI_Page "$SCRIPT_DIR/unboundstats_www.asp" "$md5_installed"
	if [ -n "$MyWebPage" ] && \
	   [ "$MyWebPage" != "NONE" ] && \
	   [ -f "$TEMP_MENU_TREE" ]
	then
		sed -i "\\~$MyWebPage~d" "$TEMP_MENU_TREE"
		rm -f "$SCRIPT_WEBPAGE_DIR/$MyWebPage"
		rm -rf "$SCRIPT_WEB_DIR" 2>/dev/null
		_FindandRemoveMenuAddOnsSection_
		umount /www/require/modules/menuTree.js
		mount -o bind "$TEMP_MENU_TREE" /www/require/modules/menuTree.js
	fi

	flock -u "$FD"
	rm -f "$SCRIPT_DIR/emptystats"
	rm -f "$SCRIPT_DIR/unboundstats_www.asp"
	rm -f "$SCRIPT_DIR/$LOG_SCRIPT_NAME_LOWER"
	rm -f "$SCRIPT_DIR/$SCRIPT_NAME_LOWER"
}

##----------------------------------------##
## Modified by Martinski W. [2025-Aug-11] ##
##----------------------------------------##
ScriptHeader()
{
	printf "\n"
	printf "##\n"
	printf "# ____ ___     ___.                            .___   _________ __          __          \n"
	printf "#|    |   \____\_ |__   ____  __ __  ____    __| _/  /   _____//  |______ _/  |_  ______\n"
	printf "#|    |   /    \| __ \ /  _ \|  |  \/    \  / __ |   \_____  \\   __\__  \\   __\/  ___/\n"
	printf "#|    |  /   |  \ \_\ (  <_> )  |  /   |  \/ /_/ |   /        \|  |  / __ \|  |  \___ \ \n"
	printf "#|______/|___|  /___  /\____/|____/|___|  /\____ |  /_______  /|__| (____  /__| /____  >\n"
	printf "#             \/    \/                  \/      \/          \/           \/          \/ \n"
	printf "## by @juched - Generate Stats for GUI tab - ${GRNct}%s [%s]${CLRct}\n" "$SCRIPT_VERSION" "$branchx_TAG"
	printf "## with credit to @JackYaz for his shared scripts\n"
	printf "\n"
}

##----------------------------------------##
## Modified by Martinski W. [2025-Jun-28] ##
##----------------------------------------##
Show_Help()
{
    printf "HELP ${MGNTct}${SCRIPT_VERS_INFO}${CLRct}\n"
	cat <<EOF
$SCRIPT_NAME_LOWER
        install      -  Installs required files for WebUI and update stats
        checkupdate  -  Checks for latest available updates, if any
        forceupdate  -  Updates to the latest version (force update)
        generate     -  Generates statistics now for WebUI
        uninstall    -  Removes files for WebUI and stops stats update
        develop      -  Switch to development branch version
        stable       -  Switch to stable/production branch version
EOF
	echo
}

##----------------------------------------##
## Modified by Martinski W. [2025-Jun-13] ##
##----------------------------------------##
Download_File()
{ /usr/sbin/curl -LSs --retry 4 --retry-delay 5 --retry-connrefused "$1" -o "$2" ; }

##-------------------------------------##
## Added by Martinski W. [2025-Jun-13] ##
##-------------------------------------##
Update_File()
{
	local tmpFile

	if [ "$1" = "unboundstats_www.asp" ]
	then
		tmpFile="/tmp/$1"
		if [ -f "$SCRIPT_DIR/$1" ]
		then
			Download_File "$SCRIPT_REPO/$1" "$tmpFile"
			if ! diff -q "$tmpFile" "$SCRIPT_DIR/$1" >/dev/null 2>&1
			then
				Get_WebUI_MD5_Installed
				Get_WebUI_Page "$SCRIPT_DIR/$1" "$md5_installed"
				sed -i "\\~$MyWebPage~d" "$TEMP_MENU_TREE"
				rm -f "$SCRIPT_WEBPAGE_DIR/$MyWebPage" 2>/dev/null
				Download_File "$SCRIPT_REPO/$1" "$SCRIPT_DIR/$1" && \
				Print_Output true "New version of $1 downloaded" "$PASS"
				[ $# -gt 1 ] && [ -n "$2" ] && Mount_WebUI
			fi
			rm -f "$tmpFile"
		else
			Download_File "$SCRIPT_REPO/$1" "$SCRIPT_DIR/$1" && \
			Print_Output true "New version of $1 downloaded" "$PASS"
			[ $# -gt 1 ] && [ -n "$2" ] && Mount_WebUI
		fi
	elif [ "$1" = "$LOG_SCRIPT_NAME_LOWER" ]
	then
		tmpFile="/tmp/$1"
		if [ -f "$SCRIPT_DIR/$1" ]
		then
			Download_File "$SCRIPT_REPO/$1" "$tmpFile"
			if ! diff -q "$tmpFile" "$SCRIPT_DIR/$1" >/dev/null 2>&1
			then
				Download_File "$SCRIPT_REPO/$1" "$SCRIPT_DIR/$1" && \
				chmod 0755 "$SCRIPT_DIR/$1" 2>/dev/null
				Print_Output true "New version of $1 downloaded" "$PASS"
				[ $# -gt 1 ] && [ -n "$2" ] && sh "$SCRIPT_DIR/$1"
			fi
			rm -f "$tmpFile"
		else
			Download_File "$SCRIPT_REPO/$1" "$SCRIPT_DIR/$1" && \
			chmod 0755 "$SCRIPT_DIR/$1" 2>/dev/null
			Print_Output true "New version of $1 downloaded" "$PASS"
			[ $# -gt 1 ] && [ -n "$2" ] && sh "$SCRIPT_DIR/$1"
		fi
	elif [ "$1" = "emptystats" ]
	then
		tmpFile="/tmp/$1"
		if [ -f "$SCRIPT_DIR/$1" ]
		then
			Download_File "$SCRIPT_REPO/$1" "$tmpFile"
			if ! diff -q "$tmpFile" "$SCRIPT_DIR/$1" >/dev/null 2>&1
			then
				Download_File "$SCRIPT_REPO/$1" "$SCRIPT_DIR/$1"
			fi
			rm -f "$tmpFile"
		else
			Download_File "$SCRIPT_REPO/$1" "$SCRIPT_DIR/$1"
		fi
	elif [ "$1" = "shared-jy.tar.gz" ]
	then
		if [ ! -f "$SHARED_DIR/${1}.md5" ]
		then
			Download_File "$SHARED_REPO/$1" "$SHARED_DIR/$1"
			Download_File "$SHARED_REPO/${1}.md5" "$SHARED_DIR/${1}.md5"
			tar -xzf "$SHARED_DIR/$1" -C "$SHARED_DIR"
			rm -f "$SHARED_DIR/$1"
			Print_Output true "New version of $1 downloaded" "$PASS"
		else
			localmd5="$(cat "$SHARED_DIR/${1}.md5")"
			remotemd5="$(curl -fsL --retry 4 --retry-delay 5 "$SHARED_REPO/${1}.md5")"
			if [ "$localmd5" != "$remotemd5" ]
			then
				Download_File "$SHARED_REPO/$1" "$SHARED_DIR/$1"
				Download_File "$SHARED_REPO/${1}.md5" "$SHARED_DIR/${1}.md5"
				tar -xzf "$SHARED_DIR/$1" -C "$SHARED_DIR"
				rm -f "$SHARED_DIR/$1"
				Print_Output true "New version of $1 downloaded" "$PASS"
			fi
		fi
	else
		return 1
	fi
}

##----------------------------------------##
## Modified by Martinski W. [2025-Jun-14] ##
##----------------------------------------##
Update_Check()
{
	local doUpdate  localVer  serverVer

	doUpdate="false"
	localVer="$(grep "SCRIPT_VERSION=" "${SCRIPT_DIR}/$SCRIPT_NAME_LOWER" | grep -m1 -oE "$scriptVersRegExp")"
	serverVer="$(curl -fsL --retry 4 --retry-delay 5 "$SCRIPT_REPO/$SCRIPT_NAME_LOWER" | grep "SCRIPT_VERSION=" | grep -m1 -oE "$scriptVersRegExp")"
	if [ "$localVer" != "$serverVer" ]
	then
		doUpdate="version"
	else
		localmd5="$(md5sum "${SCRIPT_DIR}/$SCRIPT_NAME_LOWER" | awk '{print $1}')"
		remotemd5="$(curl -fsL --retry 4 --retry-delay 5 "$SCRIPT_REPO/$SCRIPT_NAME_LOWER" | md5sum | awk '{print $1}')"
		if [ "$localmd5" != "$remotemd5" ]
		then
			doUpdate="md5"
		fi
	fi
	echo "$doUpdate,$localVer,$serverVer"
}

##----------------------------------------##
## Modified by Martinski W. [2025-Aug-11] ##
##----------------------------------------##
Update_Version()
{
	local isUpdate  localVer  serverVer

	if ! CheckFor_UnboundManager exitMsg
	then return 1
	fi

	if [ $# -gt 0 ] && [ "$1" = "check" ]
	then
		updatecheckresult="$(Update_Check)"
		isUpdate="$(echo "$updatecheckresult" | cut -f1 -d',')"
		localVer="$(echo "$updatecheckresult" | cut -f2 -d',')"
		serverVer="$(echo "$updatecheckresult" | cut -f3 -d',')"

		if [ "$isUpdate" = "version" ]
		then
			Print_Output true "New version of $SCRIPT_NAME available: ${GRNct}${serverVer}${CLRct}" "$INFO"
		elif [ "$isUpdate" = "md5" ]
		then
			Print_Output true "MD5 hash of $SCRIPT_NAME does NOT match. Hotfix available: ${GRNct}${serverVer}${CLRct}" "$INFO"
		fi

		if [ "$isUpdate" != "false" ]
		then
			printf "\n${BOLD}Do you want to continue with the update? (y/n)${CLRct}  "
			read -r confirm
			case "$confirm" in
				y|Y)
					printf "\n"
					Update_File emptystats
					Update_File shared-jy.tar.gz
					Update_File unboundstats_www.asp check
					Update_File "$LOG_SCRIPT_NAME_LOWER" check
					Download_File "$SCRIPT_REPO/$SCRIPT_NAME_LOWER" "$SCRIPT_DIR/$SCRIPT_NAME_LOWER" && \
					Print_Output true "$SCRIPT_NAME was successfully updated" "$PASS"
					chmod 0755 "$SCRIPT_DIR/$SCRIPT_NAME_LOWER" 2>/dev/null
					exit 0
				;;
				*)
					printf "\n"
					return 1
				;;
			esac
		else
			Print_Output true "No updates available. Latest version installed: ${GRNct}${localVer}${CLRct}" "$INFO"
			return 1
		fi
	fi

	if [ $# -gt 0 ] && [ "$1" = "force" ]
	then
		serverVer="$(curl -fsL --retry 4 --retry-delay 5 "$SCRIPT_REPO/$SCRIPT_NAME_LOWER" | grep "SCRIPT_VERSION=" | grep -m1 -oE "$scriptVersRegExp")"
		Print_Output true "Downloading latest version of ${SCRIPT_NAME}: ${GRNct}${serverVer}${CLRct}" "$INFO"
		Update_File emptystats
		Update_File shared-jy.tar.gz
		Update_File unboundstats_www.asp force
		Update_File "$LOG_SCRIPT_NAME_LOWER" force
		Download_File "$SCRIPT_REPO/$SCRIPT_NAME_LOWER" "$SCRIPT_DIR/$SCRIPT_NAME_LOWER" && \
		Print_Output true "$SCRIPT_NAME was successfully updated" "$PASS"
		chmod 0755 "$SCRIPT_DIR/$SCRIPT_NAME_LOWER" 2>/dev/null
		exec "$0"
		exit 0
	fi
}

##----------------------------------------##
## Modified by Martinski W. [2025-Aug-11] ##
##----------------------------------------##
Check_Dependencies()
{
	local REQS_CHECK_FAILED=false  logOpt=false

	if [ $# -gt 0 ] && [ "$1" = "startup" ]
	then logOpt=true
	fi

	if [ "$(nvram get jffs2_scripts)" -ne 1 ]
	then
		nvram set jffs2_scripts=1
		nvram commit
		Print_Output "$logOpt" "Custom JFFS Scripts enabled" "$WARN"
	fi

	if ! CheckFor_UnboundManager
	then REQS_CHECK_FAILED=true
	fi

	if [ ! -x /opt/bin/opkg ]
	then
		REQS_CHECK_FAILED=true
		Print_Output "$logOpt" "**ERROR**: Entware NOT found!" "$CRIT"
	fi

	if ! nvram get rc_support | grep -qow "am_addons"
	then
		REQS_CHECK_FAILED=true
		Print_Output "$logOpt" "Unsupported firmware version detected" "$CRIT"
		Print_Output "$logOpt" "$SCRIPT_NAME requires Merlin 384.15/384.13_4 (or later)" "$ERR"
	fi

	if "$REQS_CHECK_FAILED"
	then return 1 ; fi

	# Install SQLite if not found #
	if [ ! -f /opt/bin/sqlite3 ]
	then
		Print_Output "$logOpt" "Installing required packages from Entware" "$PASS"
		opkg update
		opkg install sqlite3-cli
		echo
	fi

	if [ $# -gt 0 ] && [ -n "$1" ] && \
        echo "$1" | grep -qE "^(install|startup)$"
	then
		Update_File emptystats
		Update_File shared-jy.tar.gz
		Update_File unboundstats_www.asp
		Update_File "$LOG_SCRIPT_NAME_LOWER"
	fi
	return 0
}

##----------------------------------------##
## Modified by Martinski W. [2025-Aug-11] ##
##----------------------------------------##
Wait_For_Unbound()
{
	if ! CheckFor_UnboundManager exitMsg
	then return 1
	fi
	if [ -n "$(pidof unbound)" ]
	then return 0
	fi

	local theSleepDelay=10  maxWaitSecs=150  theWaitSecs=0
	Print_Output true "Waiting for Unbound to be running to generate stats..." "$WARN"

	while [ -z "$(pidof unbound)" ] && [ "$theWaitSecs" -lt "$maxWaitSecs" ]
	do
		sleep "$theSleepDelay"
		theWaitSecs="$((theWaitSecs + theSleepDelay))"
		if [ "$((theWaitSecs % 30))" -eq 0 ]
		then
			Print_Output true "Waiting for Unbound to be running [$theWaitSecs secs]..." "$WARN"
		fi
	done

	if [ -n "$(pidof unbound)" ]
	then return 0
	fi
	Print_Output true "Unbound service is NOT found running after $maxWaitSecs seconds." "$CRIT"
	return 1
}

##----------------------------------------##
## Modified by Martinski W. [2025-Jun-28] ##
##----------------------------------------##
AddOn_Install()
{
	Create_Dirs
	Create_Symlinks

	if ! Check_Dependencies install
	then
		Print_Output false "Requirements for $SCRIPT_NAME not met, please see above for the reason(s)" "$CRIT"
		PressEnter ; echo
		Clear_Lock
		exit 1
	fi

	Auto_Startup delete
	Auto_ServiceEvent delete
	Auto_Cron delete
	Auto_Startup create
	Auto_ServiceEvent create
	Auto_Cron create
	Mount_WebUI
	sh "$SCRIPT_DIR/$LOG_SCRIPT_NAME_LOWER"
	Generate_UnboundStats
}

##----------------------------------------##
## Modified by Martinski W. [2025-Aug-11] ##
##----------------------------------------##
AddOn_Startup()
{
	if [ $# -eq 0 ] || [ -z "$1" ]
	then
		Print_Output true "Missing argument for startup, not starting $SCRIPT_NAME" "$ERR"
		return 1
	elif [ "$1" != "force" ]
	then
		if [ ! -x "${1}/entware/bin/opkg" ]
		then
			Print_Output true "$1 does NOT contain Entware, not starting $SCRIPT_NAME" "$CRIT"
			return 1
		else
			Print_Output true "$1 contains Entware, $SCRIPT_NAME $SCRIPT_VERSION starting up" "$PASS"
		fi
	fi

	Create_Dirs
	Create_Symlinks
	if ! Check_Dependencies startup
	then return 1
	fi
	Auto_Startup create
	Auto_ServiceEvent create
	Auto_Cron create
	Mount_WebUI
	Check_Lock
	Wait_For_Unbound
	Generate_UnboundStats
	Clear_Lock
}

##-------------------------------------##
## Added by Martinski W. [2025-Jun-28] ##
##-------------------------------------##
TMPDIR="$SHARE_TEMP_DIR"
SQLITE_TMPDIR="$TMPDIR"
export SQLITE_TMPDIR TMPDIR

##-------------------------------------##
## Added by Martinski W. [2025-Jun-13] ##
##-------------------------------------##
if [ "$SCRIPT_BRANCH" = "master" ]
then SCRIPT_VERS_INFO=""
else SCRIPT_VERS_INFO="[$version_TAG]"
fi

if [ $# -eq 0 ] || [ -z "$1" ]
then
	ScriptHeader
	Check_Dependencies
	printf "WebUI for %s is available at:\n${INFO}%s${CLRct}\n\n" "$SCRIPT_NAME" "$(Get_WebUI_URL)"
	Show_Help
	exit 0
fi

##----------------------------------------##
## Modified by Martinski W. [2025-Jun-28] ##
##----------------------------------------##
ScriptHeader
case "$1" in
	install)
		AddOn_Install
		exit 0
	;;
	startup)
		shift
		AddOn_Startup "$@"
		exit 0
	;;
	checkupdate)
		Update_Version check
		exit 0
	;;
	forceupdate)
		Update_Version force
		exit 0
	;;
	generate)
		Create_Dirs
		Create_Symlinks
		Check_Lock
		Wait_For_Unbound
		Generate_UnboundStats
		Clear_Lock
		exit 0
	;;
	service_event)
		if [ "$2" = "start" ] && [ "$3" = "$SCRIPT_NAME_LOWER" ]
		then
			Create_Dirs
			Create_Symlinks
			Check_Lock webui
			Wait_For_Unbound
			Generate_UnboundStats
			Clear_Lock
		fi
		exit 0
	;;
	uninstall)
		Auto_Startup delete
		Auto_ServiceEvent delete
		Auto_Cron delete
		Unmount_WebUI
		[ -f "$installedMD5File" ] && rm -f "$installedMD5File"
		[ -f "$ubDBASE_Stats" ] &&  rm -f "$ubDBASE_Stats"
		[ -f "$ubDBASE_Logs" ] &&  rm -f "$ubDBASE_Logs"
		Print_Output false "Uninstallation was completed." "$INFO"
		exit 0
	;;
	help)
		Show_Help
		exit 0
	;;
	develop)
		SCRIPT_BRANCH="develop"
		SCRIPT_REPO="https://raw.githubusercontent.com/juched78/Unbound-Asuswrt-Merlin/$SCRIPT_BRANCH"
		Update_Version force
		exit 0
	;;
	stable)
		SCRIPT_BRANCH="master"
		SCRIPT_REPO="https://raw.githubusercontent.com/juched78/Unbound-Asuswrt-Merlin/$SCRIPT_BRANCH"
		Update_Version force
		exit 0
	;;
	*)
		Print_Output false "Parameter [$*] is NOT recognised." "$ERR"
		Print_Output false "For a list of available commands run: $SCRIPT_NAME_LOWER help" "$INFO"
		exit 1
	;;
esac
