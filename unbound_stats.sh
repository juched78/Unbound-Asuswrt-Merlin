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
## v1.0.0 - initial text based only UI items
## v1.1.0 - March 3 2020 - Added graphs for histogram and answers, fixed install to not create duplicate tabs
## v1.1.1 - March 8 2020 - Added new install of JackYaz shared graphing files (previously needed to have one of JackYaz's other plugins installed)
## v1.1.2 - March 9 2020 - Cleanup .db and .md5 files on uninstall, move startup to post-mount, fixed directory check
## v1.2.0 - March 23 2020 - Add output for top ad blocked graph top 10 and top domains - moved stats DB to USB
## v1.2.1 - March 26 2020 - Added daily replies table
## v1.2.2 - April 5 2020 - Added tracking of client ip
## v1.2.3 - April 10 2020 - Fixed issue with "" domain name in SQL, breaking JS
## v1.2.4 - April 12 2020 - Removed error message on clean install for missing md5 file
## v1.2.5 - April 13 2020 - During install, do not Generate stats if unbound is not running
## v1.3.0 - April 16 2020 - Show stats for DNS Firewall
## v1.4.0 - March 7 2021 - Introduce locking standard around mounting and unmouning, increase max pages to 20
## v1.4.1 - April 6 2021 - Fix statup timeout killing init, (missing tabs, double data, etc).
readonly SCRIPT_VERSION="v1.4.1"

#define www script names
readonly SCRIPT_WEBPAGE_DIR="$(readlink /www/user)"
readonly SCRIPT_NAME="Unbound_Stats.sh"
readonly LOGSCRIPT_NAME="Unbound_Log.sh"
readonly SCRIPT_NAME_LOWER="unbound_stats.sh"
readonly LOGSCRIPT_NAME_LOWER="unbound_log.sh"
readonly SCRIPT_WEB_DIR="$SCRIPT_WEBPAGE_DIR/$SCRIPT_NAME_LOWER"

readonly SCRIPT_DIR="/jffs/addons/unbound"

#needed for shared jy graph files from @JackYaz
readonly SHARED_DIR="/jffs/addons/shared-jy"
readonly SHARED_REPO="https://raw.githubusercontent.com/jackyaz/shared-jy/master"
readonly SHARED_WEB_DIR="$SCRIPT_WEBPAGE_DIR/shared-jy"

#define needed commands
readonly UNBOUNCTRLCMD="unbound-control"

#define data file names
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

#DB file to hold data for uptime graph
dbOldStats="$SCRIPT_DIR/unboundstats.db"
dbStats="/opt/var/lib/unbound/unbound_stats.db"
dbLogs="/opt/var/lib/unbound/unbound_log.db"

#save md5 of last installed www ASP file so you can find it again later (in case of www ASP update)
installedMD5File="$SCRIPT_DIR/www-installed.md5"

#get sqlite path
[ -f /opt/bin/sqlite3 ] && SQLITE3_PATH=/opt/bin/sqlite3 || SQLITE3_PATH=/usr/sbin/sqlite3

#function to create JS file with data
WriteStats_ToJS(){
	[ -f $2 ] && rm -f "$2"
	echo "function $3(){" >> "$2"
	html='document.getElementById("'"$4"'").innerHTML="'
	while IFS='' read -r line || [ -n "$line" ]; do
		html="$html""$line""\\r\\n"
	done < "$1"
	html="$html"'"'
	printf "%s\\r\\n}\\r\\n" "$html" >> "$2"
}

WriteData_ToJS(){
	{
	echo "var $3;"
	echo "$3 = [];"; } >> "$2"
	contents="$3"'.unshift( '
	while IFS='' read -r line || [ -n "$line" ]; do
		if echo "$line" | grep -q "NaN"; then continue; fi
		if [ "$4" == "date-day" ]; then
			datapoint="{ x: moment(\"""$(echo "$line" | awk 'BEGIN{FS=","}{ print $1 }' | awk '{$1=$1};1')""\", \"YYYY-MM-DD\"), y: ""$(echo "$line" | awk 'BEGIN{FS=","}{ print $2 }' | awk '{$1=$1};1')"" }"
		else	
			datapoint="{ x: moment.unix(""$(echo "$line" | awk 'BEGIN{FS=","}{ print $1 }' | awk '{$1=$1};1')""), y: ""$(echo "$line" | awk 'BEGIN{FS=","}{ print $2 }' | awk '{$1=$1};1')"" }"
		fi
		contents="$contents""$datapoint"","
	done < "$1"
	contents=$(echo "$contents" | sed 's/.$//')
	contents="$contents"");"
	printf "%s\\r\\n\\r\\n" "$contents" >> "$2"
}

#$1varible name $2 filename $3 rawStatsFile $4 on fields to add
WriteUnboundStats_ToJS(){
	outputvar="$1"
	inputfile="$3"
	outputfile="$2"
	outputlist=""
	shift;shift;shift
	for var in "$@"; do
		item="$(awk -v pat="$var=" 'BEGIN {FS="[= ]"}$0 ~ pat {print $2}' $inputfile)"
		if [ -z "$outputlist" ]; then
			outputlist=$item
		else
			outputlist=$outputlist", "$item
		fi
	done

	{ echo "var $outputvar;"
		echo "$outputvar = [];"
		echo "${outputvar}.unshift($outputlist);"
		echo; } >> "$outputfile"
}

#$1varible name $2 filename $3 on fields to add
WriteUnboundLabels_ToJS(){
	outputvar="$1"
	outputfile="$2"
	outputlist=""
	shift;shift
	for var in "$@"; do
		if [ -z "$outputlist" ]; then
			outputlist=\"$var\"
		else
			outputlist=$outputlist", "\"$var\"
		fi
	done

	{ echo "var $outputvar;"
		echo "$outputvar = [];"
		echo "${outputvar}.unshift($outputlist);"
		echo; } >> "$outputfile"
}

#$1sql table $2 label column $3 count column $4 limit count $5 csv file $6 sql file $7 where clasue if needed
WriteUnboundSqlLog_ToFile(){
	{
		echo ".mode csv"
		echo ".output $5"
	} > "$6"
	echo "SELECT $2, SUM($3) FROM $1 $7 GROUP BY $2 ORDER BY SUM($3) DESC LIMIT $4;" >> "$6"
}

#$1 csv file $2 js file $3 varLabel $4 varData
WriteUnboundCSV_ToJS() {
	labels="$3"'.unshift( '
	values="$4"'.unshift( '
	while IFS='' read -r line || [ -n "$line" ]; do
		if echo "$line" | grep -q "NaN"; then continue; fi
		labels="$labels""$(echo "$line" | awk 'BEGIN{FS=","}{ print "\x27" $1 "\x27" }' | awk '{$1=$1};1')"","
		values="$values""$(echo "$line" | awk 'BEGIN{FS=","}{ print $2 }' | awk '{$1=$1};1')"","
	done < "$1"
	labels=$(echo "$labels" | sed 's/.$//')
	labels="$labels"");"
	values=$(echo "$values" | sed 's/.$//')
	values="$values"");"

	{
	echo "var $3;"
	echo "$3 = [];"; } >> "$2"
	printf "%s\\r\\n\\r\\n" "$labels" >> "$2"
	{
	echo "var $4;"
	echo "$4 = [];"; } >> "$2"
	printf "%s\\r\\n\\r\\n" "$values" >> "$2"
}

#$1 csv file $2 js file $3 varLabel $4 varData
WriteUnboundCSV_ToJS_2Labels() {
	labels="$3"'.unshift( '
	values="$4"'.unshift( '
	while IFS='' read -r line || [ -n "$line" ]; do
		if echo "$line" | grep -q "NaN"; then continue; fi
		labels="$labels""$(echo "$line" | awk 'BEGIN{FS=","}{ print "\x27" $1 " (" $2 ")\x27" }' | awk '{$1=$1};1')"","
		values="$values""$(echo "$line" | awk 'BEGIN{FS=","}{ print $3 }' | awk '{$1=$1};1')"","
	done < "$1"
	labels=$(echo "$labels" | sed 's/.$//')
	labels="$labels"");"
	values=$(echo "$values" | sed 's/.$//')
	values="$values"");"

	{
	echo "var $3;"
	echo "$3 = [];"; } >> "$2"
	printf "%s\\r\\n\\r\\n" "$labels" >> "$2"
	{
	echo "var $4;"
	echo "$4 = [];"; } >> "$2"
	printf "%s\\r\\n\\r\\n" "$values" >> "$2"
}

#$1 csv file $2 JS file $3 JS func name $4 html tag
WriteUnboundCSV_ToJS_Table() {
	#clean up any null (or "") strings with null string
	sed -i 's/""/null/g' "$1"

	[ -f $2 ] && rm -f "$2"
	echo "function $3(){" >> "$2"
	html='document.getElementById("'"$4"'").outerHTML="'
	numLines="$(wc -l < $1)"
	if [ "$numLines" -lt 1 ]; then
		html="$html""<tr><td colspan="4" class="nodata">No data to display</td></tr>"
	else
		html="$html""$(cat "$1" | awk 'BEGIN{FS=","}{ print "<tr><td>" $1 "</td><td>" $2 "</td><td>"$3 "</td><td>" $4 "</td></tr> \\" }' | awk '{$1=$1};1')"
	fi
	html=${html%?}
	html="$html"'"'
	printf "%s}" "$html" >> "$2"
} 

#$1 fieldname $2 tablename $3 frequency (hours) $4 length (days) $5 outputfile $6 sqlfile
WriteSql_ToFile(){
	{
		echo ".mode csv"
		echo ".output $5"
	} >> "$6"
	COUNTER=0
	timenow="$(date '+%s')"
	until [ $COUNTER -gt "$((24*$4/$3))" ]; do
		echo "select $timenow - ((60*60*$3)*($COUNTER)),IFNULL(avg([$1]),'NaN') from $2 WHERE ([Timestamp] >= $timenow - ((60*60*$3)*($COUNTER+1))) AND ([Timestamp] <= $timenow - ((60*60*$3)*$COUNTER));" >> "$6"
		COUNTER=$((COUNTER + 1))
	done
}

Generate_UnboundStats () {
	#generate stats to raw file
	if [ -n "$(pidof unbound)" ]; then 
		printf "$($UNBOUNCTRLCMD stats_noreset)" > $raw_statsFile
	else
		#output empty data, cannot get new stats
		cat /jffs/addons/unbound/emptystats > $raw_statsFile
	fi
	
	#generate header
	LINE=" --------------------------------------------------------\\n"
	printf "\\n Standard Statistics\\n$LINE" >${statsFile}
	
	#output text stats for box
	UNB_NUM_Q="$(awk 'BEGIN {FS="[= ]"} /total.num.queries=/ {print $2}' $raw_statsFile )"
	UNB_NUM_CH="$(awk 'BEGIN {FS="[= ]"} /total.num.cachehits=/ {print $2}' $raw_statsFile )"
	printf "\\n Number of DNS queries: %s" "$UNB_NUM_Q" >> $statsFile
	printf "\\n Number of queries that were successfully answered using cache lookup (ie. cache hit): %s" "$UNB_NUM_CH" >> $statsFile
	printf "$(awk 'BEGIN {FS="[= ]"} /total.num.cachemiss=/ {print "\\n Number of queries that needed recursive lookup (ie. cache miss): " $2}' $raw_statsFile )" >> $statsFile
	printf "$(awk 'BEGIN {FS="[= ]"} /total.num.zero_ttl=/ {print "\\n Number of replies that were served by an expired cache entry: " $2}' $raw_statsFile )" >> $statsFile
	printf "$(awk 'BEGIN {FS="[= ]"} /total.requestlist.exceeded=/ {print "\\n Number of queries dropped because request list was full: " $2}' $raw_statsFile )" >> $statsFile
	printf "$(awk 'BEGIN {FS="[= ]"} /total.requestlist.avg=/ {print "\\n Average number of requests in list for recursive processing: " $2}' $raw_statsFile )" >> $statsFile
	
	#extended stats
	if [ -n "$(pidof unbound)" ] && [ "$($UNBOUNCTRLCMD get_option extended-statistics)" == "yes" ];then 
		printf "\\n\\n Extended Statistics\\n$LINE" >> $statsFile
		printf "$(awk 'BEGIN {FS="[= ]"} /mem.cache.rrset=/ {print "\\n RRset cache usage in bytes: " $2}' $raw_statsFile )" >> $statsFile
		printf "$(awk 'BEGIN {FS="[= ]"} /mem.cache.message=/ {print "\\n Message cache usage in bytes: " $2}' $raw_statsFile )" >> $statsFile
 	fi

	#adblock stats
	if [ -f /opt/var/lib/unbound/adblock/adservers ] && [ -f $adblockStatsFile ]; then
		printf "\\n\\n Adblock Statistics\\n$LINE" >> $statsFile
		printf "$(cat $adblockStatsFile )" >> $statsFile
	fi
	
	#calc % served by cache
	if [ ! -z "$UNB_NUM_Q" ] && [ $UNB_NUM_Q -ne 0 ]; then
		UNB_CHP="$(awk 'BEGIN {printf "%0.2f", '$UNB_NUM_CH'*100/'$UNB_NUM_Q'}' )"
	else
		UNB_CHP=0
	fi
	echo "Calculated Cache Hit Percentage: $UNB_CHP"
	printf "$(awk 'BEGIN {printf "\\n\\n Cache hit success percent: %s", '$UNB_CHP'}' )" >> $statsFile
	
	#create JS file to be loaded by web page
	WriteStats_ToJS "$statsFile" "$statsFileJS" "SetUnboundStats" "unboundstats"
	
	echo "Unbound Stats generated on $(date +"%c")" > $statsTitleFile
	WriteStats_ToJS "$statsTitleFile" "$statsTitleFileJS" "SetUnboundStatsTitle" "unboundstatstitle"

	#use SQLite to track % for graph
	echo "Adding new value to DB..."
	{
		echo "CREATE TABLE IF NOT EXISTS [unboundstats] ([StatID] INTEGER PRIMARY KEY NOT NULL, [Timestamp] NUMERIC NOT NULL, [CacheHitPercent] REAL NOT NULL);"
		echo "INSERT INTO unboundstats ([Timestamp],[CacheHitPercent]) values($(date '+%s'),$UNB_CHP);"
	} > /tmp/unbound-stats.sql
	
	"$SQLITE3_PATH" "$dbStats" < /tmp/unbound-stats.sql

	echo "Calculating Daily data..."
	{
		echo ".mode csv"
		echo ".output /tmp/unbound-chp-daily.csv"
		echo "select [Timestamp],[CacheHitPercent] from unboundstats WHERE [Timestamp] >= (strftime('%s','now') - 86400);"
	} > /tmp/unbound-stats.sql
	
	"$SQLITE3_PATH" "$dbStats" < /tmp/unbound-stats.sql
	rm -f /tmp/unbound-stats.sql

	echo "Calculating Weekly and Monthly data..."
	WriteSql_ToFile "CacheHitPercent" "unboundstats" 1 7 "/tmp/unbound-chp-weekly.csv" "/tmp/unbound-stats.sql"
	WriteSql_ToFile "CacheHitPercent" "unboundstats" 3 30 "/tmp/unbound-chp-monthly.csv" "/tmp/unbound-stats.sql"
	
	"$SQLITE3_PATH" "$dbStats" < /tmp/unbound-stats.sql
	
	[ -f $statsCHPFileJS ] && rm -f "$statsCHPFileJS"
	WriteData_ToJS "/tmp/unbound-chp-daily.csv" "$statsCHPFileJS" "DatadivLineChartCacheHitPercentDaily"
	WriteData_ToJS "/tmp/unbound-chp-weekly.csv" "$statsCHPFileJS" "DatadivLineChartCacheHitPercentWeekly"
	WriteData_ToJS "/tmp/unbound-chp-monthly.csv" "$statsCHPFileJS" "DatadivLineChartCacheHitPercentMonthly"

	#generate data for histogram on performance
	echo "Outputting histogram performance data..."
	[ -f $statsHistogramFileJS ] && rm -f $statsHistogramFileJS
	WriteUnboundStats_ToJS "barDataHistogram" $statsHistogramFileJS $raw_statsFile "histogram.000000.000000.to.000000.000001" "histogram.000000.000001.to.000000.000002" "histogram.000000.000002.to.000000.000004" "histogram.000000.000004.to.000000.000008" "histogram.000000.000008.to.000000.000016" "histogram.000000.000016.to.000000.000032" "histogram.000000.000032.to.000000.000064" "histogram.000000.000064.to.000000.000128" "histogram.000000.000128.to.000000.000256" "histogram.000000.000256.to.000000.000512" "histogram.000000.000512.to.000000.001024" "histogram.000000.001024.to.000000.002048" "histogram.000000.002048.to.000000.004096" "histogram.000000.004096.to.000000.008192" "histogram.000000.008192.to.000000.016384" "histogram.000000.016384.to.000000.032768" "histogram.000000.032768.to.000000.065536" "histogram.000000.065536.to.000000.131072" "histogram.000000.131072.to.000000.262144" "histogram.000000.262144.to.000000.524288" "histogram.000000.524288.to.000001.000000" "histogram.000001.000000.to.000002.000000" "histogram.000002.000000.to.000004.000000" "histogram.000004.000000.to.000008.000000" "histogram.000008.000000.to.000016.000000" "histogram.000016.000000.to.000032.000000" "histogram.000032.000000.to.000064.000000" "histogram.000064.000000.to.000128.000000" "histogram.000128.000000.to.000256.000000" "histogram.000256.000000.to.000512.000000" "histogram.000512.000000.to.001024.000000" "histogram.001024.000000.to.002048.000000" "histogram.002048.000000.to.004096.000000" "histogram.004096.000000.to.008192.000000" "histogram.008192.000000.to.016384.000000" "histogram.016384.000000.to.032768.000000" "histogram.032768.000000.to.065536.000000" "histogram.065536.000000.to.131072.000000" "histogram.131072.000000.to.262144.000000" "histogram.262144.000000.to.524288.000000"
	WriteUnboundLabels_ToJS "barLabelsHistogram" $statsHistogramFileJS "0us - 1us" "1us - 2us" "2us - 4us" "4us - 8us" "8us - 16us" "16us - 32us" "32us - 64us" "64us - 128us" "128us - 256us" "256us - 512us" "512us - 1ms" "1ms - 2ms" "2ms - 4ms" "4ms - 8ms" "8ms - 16ms" "16ms - 32ms" "32ms - 65ms" "65ms - 131ms" "131ms - 262ms" "262ms - 524ms" "524ms - 1s" "1s - 2s" "2s - 4s" "4s - 8s" "8s - 16s" "16s - 32s" "32s - 1m" "1m - 2m" "2m - 4m" "4m - 8.5m" "8.5m - 17m" "17m - 34m" "34m - 1h" "1h - 2.3h" "2.3h - 4.5h" "4.5h - 9.1h" "9.1h - 18.2h" "18.2h - 36.4h" "36.4h - 72.6h" "72.8h - 145.6h"

	#generate data for answers
	echo "Outputting answers data..."
	[ -f $statsAnswersFileJS ] && rm -f $statsAnswersFileJS
	WriteUnboundStats_ToJS "barDataAnswers" $statsAnswersFileJS $raw_statsFile "num.answer.rcode.NOERROR" "num.answer.rcode.FORMERR" "num.answer.rcode.SERVFAIL" "num.answer.rcode.NXDOMAIN" "num.answer.rcode.NOTIMPL" "num.answer.rcode.REFUSED"
	WriteUnboundLabels_ToJS "barLabelsAnswers" $statsAnswersFileJS "DNS Query completed successfully" "DNS Query Format Error" "Server failed to complete the DNS request" "Domain name does not exist  (including adblock if enabled)" "Function not implemented" "The server refused to answer for the query"

	#generate data for top blocked domains
	echo "Outputting top blocked domains..."
	[ -f $statsTopBlockedFileJS ] && rm -f $statsTopBlockedFileJS
	WriteUnboundSqlLog_ToFile "nx_domains" "domain" "count" "15" "/tmp/unbound-tbd.csv" "/tmp/unbound-tbd.sql"
	"$SQLITE3_PATH" "$dbLogs" < /tmp/unbound-tbd.sql
	WriteUnboundCSV_ToJS "/tmp/unbound-tbd.csv" "$statsTopBlockedFileJS" "barLabelsTopBlocked" "barDataTopBlocked"

	#generate data for top 10 weekly replies from unbound
	echo "Outputting top replies ..."
	[ -f $statsTopRepliesFileJS ] && rm -f $statsTopRepliesFileJS
	WriteUnboundSqlLog_ToFile "reply_domains" "domain, reply" "count" "15" "/tmp/unbound-topreplies.csv" "/tmp/unbound-topreplies.sql"
	"$SQLITE3_PATH" "$dbLogs" < /tmp/unbound-topreplies.sql
	WriteUnboundCSV_ToJS_2Labels "/tmp/unbound-topreplies.csv" "$statsTopRepliesFileJS" "barLabelsTopReplies" "barDataTopReplies"

	#generate daily replies CSV
	echo "Outputting daily replies ..."
	[ -f $statsDailyRepliesFileJS ] && rm -f $statsDailyRepliesFileJS
	whereString="WHERE date='""$(date '+%F')""'"
	WriteUnboundSqlLog_ToFile "reply_domains" "domain, client_ip, reply" "count" "250" "/tmp/unbound-dailyreplies.csv" "/tmp/unbound-dailyreplies.sql" "$whereString"
	"$SQLITE3_PATH" "$dbLogs" < /tmp/unbound-dailyreplies.sql
	dos2unix "/tmp/unbound-dailyreplies.csv"
	WriteUnboundCSV_ToJS_Table "/tmp/unbound-dailyreplies.csv" $statsDailyRepliesFileJS "LoadDailyRepliesTable" "DatadivTableDailyReplies"

	#generate DNS Firewall Events (RPZ)
	echo "Calculating DNS Firewall data..."
	{
		echo ".mode csv"
		echo ".output /tmp/unbound-rpz-monthly.csv"
		echo "select [date],SUM(count) from rpz_events GROUP BY date ORDER BY date;"
	} > /tmp/unbound-rpz.sql
	
	"$SQLITE3_PATH" "$dbLogs" < /tmp/unbound-rpz.sql
	[ -f $statsRPZFileJS ] && rm -f "$statsRPZFileJS"
	WriteData_ToJS "/tmp/unbound-rpz-monthly.csv" "$statsRPZFileJS" "DatadivLineChartRPZHitsMonthly" "date-day"

	#generate table data for all known RPZ hits
	echo "Outputting DNS Firewall Hits ..."
	[ -f $statsRPZHItsFileJS ] && rm -f $statsRPZHitsFileJS
	whereString=""
	WriteUnboundSqlLog_ToFile "rpz_events" "domain, client_ip, zone" "count" "250" "/tmp/unbound-rpzhits.csv" "/tmp/unbound-rpzhits.sql" "$whereString"
	"$SQLITE3_PATH" "$dbLogs" < /tmp/unbound-rpzhits.sql
	dos2unix "/tmp/unbound-rpzhits.csv"
	WriteUnboundCSV_ToJS_Table "/tmp/unbound-rpzhits.csv" $statsRPZHitsFileJS "LoadRPZHitsTable" "DatadivTableRPZHits"

	#cleanup temp files
	rm -f "/tmp/unbound-"*".csv"
	rm -f "/tmp/unbound-"*".sql"
	[ -f $raw_statsFile ] && rm -f $raw_statsFile
	[ -f $statsFile ] && rm -f $statsFile
	[ -f $statsTitleFile ] && rm -f $statsTitleFile
}

Auto_Startup(){
	case $1 in
		create)
			if [ -f /jffs/scripts/post-mount ]; then
				STARTUPLINECOUNTEX=$(grep -cx "$SCRIPT_DIR/$SCRIPT_NAME_LOWER startup"' "$@" & # '"$SCRIPT_NAME" /jffs/scripts/post-mount)
				
				if [ "$STARTUPLINECOUNTEX" -eq 0 ]; then
					echo "$SCRIPT_DIR/$SCRIPT_NAME_LOWER startup"' "$@" & # '"$SCRIPT_NAME" >> /jffs/scripts/post-mount
				fi
			else
				echo "#!/bin/sh" > /jffs/scripts/post-mount
				echo "" >> /jffs/scripts/post-mount
				echo "$SCRIPT_DIR/$SCRIPT_NAME_LOWER startup"' "$@" & # '"$SCRIPT_NAME" >> /jffs/scripts/post-mount
				chmod 0755 /jffs/scripts/post-mount
			fi
		;;
		delete)
			if [ -f /jffs/scripts/post-mount ]; then
				STARTUPLINECOUNT=$(grep -c '# '"$SCRIPT_NAME" /jffs/scripts/post-mount)
				
				if [ "$STARTUPLINECOUNT" -gt 0 ]; then
					sed -i -e '/# '"$SCRIPT_NAME"'/d' /jffs/scripts/post-mount
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
				cru a "$SCRIPT_NAME" "59 * * * * $SCRIPT_DIR/$SCRIPT_NAME_LOWER generate"
			fi
			STARTUPLINECOUNT=$(cru l | grep -c "$LOGSCRIPT_NAME")
			
			if [ "$STARTUPLINECOUNT" -eq 0 ]; then
				cru a "$LOGSCRIPT_NAME" "57 * * * * $SCRIPT_DIR/$LOGSCRIPT_NAME_LOWER"
			fi
		;;
		delete)
			STARTUPLINECOUNT=$(cru l | grep -c "$SCRIPT_NAME")
			
			if [ "$STARTUPLINECOUNT" -gt 0 ]; then
				cru d "$SCRIPT_NAME"
			fi
			STARTUPLINECOUNT=$(cru l | grep -c "$LOGSCRIPT_NAME")
			
			if [ "$STARTUPLINECOUNT" -gt 0 ]; then
				cru d "$LOGSCRIPT_NAME"
			fi
		;;
	esac
}

Auto_ServiceEvent(){
	case $1 in
		create)
			if [ -f /jffs/scripts/service-event ]; then
				# shellcheck disable=SC2016
				STARTUPLINECOUNTEX=$(grep -cx "$SCRIPT_DIR/$SCRIPT_NAME_LOWER generate"' "$1" "$2" &'' # '"$SCRIPT_NAME" /jffs/scripts/service-event)
				
				if [ "$STARTUPLINECOUNTEX" -eq 0 ]; then
					# shellcheck disable=SC2016
					echo "$SCRIPT_DIR/$SCRIPT_NAME_LOWER generate"' "$1" "$2" &'' # '"$SCRIPT_NAME" >> /jffs/scripts/service-event
			fi
			else
				echo "#!/bin/sh" > /jffs/scripts/service-event
				echo "" >> /jffs/scripts/service-event
				# shellcheck disable=SC2016
				echo "/jffs/scripts/$SCRIPT_NAME_LOWER generate"' "$1" "$2" &'' # '"$SCRIPT_NAME" >> /jffs/scripts/service-event
				chmod 0755 /jffs/scripts/service-event
			fi
		;;
		delete)
			if [ -f /jffs/scripts/service-event ]; then
				STARTUPLINECOUNT=$(grep -c '# '"$SCRIPT_NAME" /jffs/scripts/service-event)
				
				if [ "$STARTUPLINECOUNT" -gt 0 ]; then
					sed -i -e '/# '"$SCRIPT_NAME"'/d' /jffs/scripts/service-event
				fi
			fi
		;;
	esac
}


Create_Dirs(){

	if [ ! -d "$SCRIPT_WEBPAGE_DIR" ]; then
		mkdir -p "$SCRIPT_WEBPAGE_DIR"
	fi
	
	if [ ! -d "$SCRIPT_WEB_DIR" ]; then
		mkdir -p "$SCRIPT_WEB_DIR"
	fi

	# migrate to USB key, to aviod using space on JFFs
	if [ -f "$dbOldStats" ]; then
		mv $dbOldStats $dbStats
	fi
}

Get_WebUI_Installed () {
	md5_installed="0"
	if [ -f $installedMD5File ]; then
		md5_installed="$(cat $installedMD5File)"
	fi
}

Get_WebUI_Page () {
	for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
		page="$SCRIPT_WEBPAGE_DIR/user$i.asp"
		if [ ! -f "$page" ] || [ "$(md5sum < "$1")" = "$(md5sum < "$page")" ] || [ "$2" = "$(md5sum < "$page")" ]; then
			MyPage="user$i.asp"
			return
		fi
	done
	MyPage="none"
}

Mount_WebUI(){
	if nvram get rc_support | grep -qF "am_addons"; then
	
		### locking mechanism code credit to Martineau (@MartineauUK) ###
		LOCKFILE=/tmp/addonwebui.lock
		FD=386
		eval exec "$FD>$LOCKFILE"
		flock -x "$FD"
		
		Get_WebUI_Installed
		Get_WebUI_Page "$SCRIPT_DIR/unboundstats_www.asp" "$md5_installed"
		if [ "$MyPage" = "none" ]; then
			echo "Unable to mount $SCRIPT_NAME WebUI page, exiting"
			flock -u "$FD"		
			exit 1
		fi
		echo "Mounting $SCRIPT_NAME WebUI page as $MyPage"
		cp -f "$SCRIPT_DIR/unboundstats_www.asp" "$SCRIPT_WEBPAGE_DIR/$MyPage"
		echo "Saving MD5 of installed file $SCRIPT_DIR/unboundstats_www.asp to $installedMD5File"
		md5sum < "$SCRIPT_DIR/unboundstats_www.asp" > $installedMD5File
		
		if [ ! -f "/tmp/index_style.css" ]; then
			cp -f "/www/index_style.css" "/tmp/"
		fi
		
		if ! grep -q '.menu_Addons' /tmp/index_style.css ; then
			echo ".menu_Addons { background: url(ext/shared-jy/addons.png); }" >> /tmp/index_style.css
		fi
		
		umount /www/index_style.css 2>/dev/null
		mount -o bind /tmp/index_style.css /www/index_style.css
		
		if [ ! -f "/tmp/menuTree.js" ]; then
			cp -f "/www/require/modules/menuTree.js" "/tmp/"
		fi
		
		sed -i "\\~$MyPage~d" /tmp/menuTree.js
		
		if ! grep -q 'menuName: "Addons"' /tmp/menuTree.js ; then
			lineinsbefore="$(( $(grep -n "exclude:" /tmp/menuTree.js | cut -f1 -d':') - 1))"
			sed -i "$lineinsbefore"'i,\n{\nmenuName: "Addons",\nindex: "menu_Addons",\ntab: [\n{url: "ext/shared-jy/redirect.htm", tabName: "Help & Support"},\n{url: "NULL", tabName: "__INHERIT__"}\n]\n}' /tmp/menuTree.js
		fi
		
		if grep -q "javascript:window.open('/ext/shared-jy/redirect.htm'" /tmp/menuTree.js ; then
			sed -i "s~javascript:window.open('/ext/shared-jy/redirect.htm','_blank')~javascript:var helpwindow=window.open('/ext/shared-jy/redirect.htm','_blank')~" /tmp/menuTree.js
		fi
		if ! grep -q "javascript:var helpwindow=window.open('/ext/shared-jy/redirect.htm'" /tmp/menuTree.js ; then
			sed -i "s~ext/shared-jy/redirect.htm~javascript:var helpwindow=window.open('/ext/shared-jy/redirect.htm','_blank')~" /tmp/menuTree.js
		fi
		sed -i "/url: \"javascript:var helpwindow=window.open('\/ext\/shared-jy\/redirect.htm'/i {url: \"$MyPage\", tabName: \"Unbound\"}," /tmp/menuTree.js
		
		umount /www/require/modules/menuTree.js 2>/dev/null
		mount -o bind /tmp/menuTree.js /www/require/modules/menuTree.js
		
		flock -u "$FD"
	fi
}

Unmount_WebUI(){
	### locking mechanism code credit to Martineau (@MartineauUK) ###
	LOCKFILE=/tmp/addonwebui.lock
	FD=386
	eval exec "$FD>$LOCKFILE"
	flock -x "$FD"
	
	Get_WebUI_Installed
	Get_WebUI_Page "$SCRIPT_DIR/unboundstats_www.asp" "$md5_installed" 
	echo "$MyPage"
	if [ -n "$MyPage" ] && [ "$MyPage" != "none" ] && [ -f "/tmp/menuTree.js" ]; then
		sed -i "\\~$MyPage~d" /tmp/menuTree.js
		umount /www/require/modules/menuTree.js
		mount -o bind /tmp/menuTree.js /www/require/modules/menuTree.js
		rm -rf "$SCRIPT_WEBPAGE_DIR/$MyPage"
		rm -rf "$SCRIPT_WEB_DIR"
	fi
	
	flock -u "$FD"
}

# $1 show commands
ScriptHeader() { 
	printf "\\n"
	printf "##\\n"
	printf "# ____ ___     ___.                            .___   _________ __          __          \\n"
	printf "#|    |   \____\_ |__   ____  __ __  ____    __| _/  /   _____//  |______ _/  |_  ______\\n"
	printf "#|    |   /    \| __ \ /  _ \|  |  \/    \  / __ |   \_____  \\   __\__  \\   __\/  ___/\\n"
	printf "#|    |  /   |  \ \_\ (  <_> )  |  /   |  \/ /_/ |   /        \|  |  / __ \|  |  \___ \ \\n"
	printf "#|______/|___|  /___  /\____/|____/|___|  /\____ |  /_______  /|__| (____  /__| /____  >\\n"
	printf "#             \/    \/                  \/      \/          \/           \/          \/ \\n"
	printf "## by @juched - Generate Stats for GUI tab - %s                                         \\n" "$SCRIPT_VERSION"
	printf "## with credit to @JackYaz for his shared scripts                                       \\n"
	printf "\\n"
	if [ ! -z $1 ]; then
		printf "unbound_stats.sh\\n"
		printf "		install   - Installs the needed files to show UI and update stats\\n"
		printf "		generate  - enerates statistics now for UI\\n"
		printf "		uninstall - Removes files needed for UI and stops stats update\\n"
	fi
}

Download_File(){
	/usr/sbin/curl -fsL --retry 3 "$1" -o "$2"
}

Install_Dependancies(){
	#install SQLite if not installed
	if [ ! -f /opt/bin/sqlite3 ]; then
		echo "Installing required version of sqlite3 from Entware"
		opkg update
		opkg install sqlite3-cli
	fi

	# make shared JY charts directory, and download if needed
	if [ ! -d "$SHARED_DIR" ]; then
		echo "Shared JY directory doesn't exist, let's make it..."
		mkdir "$SHARED_DIR"
	fi
	if [ ! -f "$SHARED_DIR/shared-jy.tar.gz.md5" ]; then
		Download_File "$SHARED_REPO/shared-jy.tar.gz" "$SHARED_DIR/shared-jy.tar.gz"
		Download_File "$SHARED_REPO/shared-jy.tar.gz.md5" "$SHARED_DIR/shared-jy.tar.gz.md5"
		tar -xzf "$SHARED_DIR/shared-jy.tar.gz" -C "$SHARED_DIR"
		rm -f "$SHARED_DIR/shared-jy.tar.gz"
		echo "New version of shared-jy.tar.gz downloaded"
	else
		localmd5="$(cat "$SHARED_DIR/shared-jy.tar.gz.md5")"
		remotemd5="$(curl -fsL --retry 3 "$SHARED_REPO/shared-jy.tar.gz.md5")"
		if [ "$localmd5" != "$remotemd5" ]; then
			Download_File "$SHARED_REPO/shared-jy.tar.gz" "$SHARED_DIR/shared-jy.tar.gz"
			Download_File "$SHARED_REPO/shared-jy.tar.gz.md5" "$SHARED_DIR/shared-jy.tar.gz.md5"
			tar -xzf "$SHARED_DIR/shared-jy.tar.gz" -C "$SHARED_DIR"
			rm -f "$SHARED_DIR/shared-jy.tar.gz"
			echo "New version of shared-jy.tar.gz downloaded"
		fi
	fi

	#Symlink the shared jy folder if it doesn't exist
	if [ ! -d "$SHARED_WEB_DIR" ]; then
		ln -s "$SHARED_DIR" "$SHARED_WEB_DIR" 2>/dev/null
	fi
}

Wait_For_Unbound() {
	echo "Checking if Unbound is running to generate stats..."
        WAIT=10    #give 150 seconds or so for unbound to start 
        I=0
         while [ $I -lt $((WAIT)) ]
            do
                if [ ! -z "$(pidof unbound)" ]; then
			break;
		fi
		echo "Unbound not running yet, try again $I..."
                sleep 15
                I=$((I + 1))
            done  
}

#Main loop
if [ -z "$1" ]; then
	ScriptHeader show_commands
	exit 0
fi

ScriptHeader
case "$1" in
	install)
		Install_Dependancies
		Auto_Startup delete
		Auto_ServiceEvent delete
		Auto_Cron delete
		Auto_Startup create
		Auto_ServiceEvent create
		Auto_Cron create
		Mount_WebUI
		Create_Dirs
		sh /jffs/addons/unbound/unbound_log.sh
		Generate_UnboundStats
		exit 0
	;;
	startup)
		# only start on entware mount	
		if [ -f "$2/entware/bin/opkg" ]; then
			echo "Found entware mount... startup now..."
			Auto_Cron create
			Mount_WebUI
			Create_Dirs
			Wait_For_Unbound
			Generate_UnboundStats
		fi
		exit 0
	;;
	generate)
		if [ -z "$2" ] && [ -z "$3" ]; then
			Wait_For_Unbound
			Generate_UnboundStats
		elif [ "$2" = "start" ] && [ "$3" = "$SCRIPT_NAME_LOWER" ]; then
			Wait_For_Unbound
			Generate_UnboundStats
		fi
		exit 0
	;;
	uninstall)
		Auto_Startup delete
		Auto_ServiceEvent delete
		Auto_Cron delete
		Unmount_WebUI
		[ -f $installedMD5File ] && rm -f $installedMD5File
		[ -f $dbStats ] &&  rm -f $dbStats
		[ -f $dbLogs ] &&  rm -f $dbLogs
		exit 0
	;;
esac
