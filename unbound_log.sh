#!/bin/sh 
##
# ____ ___     ___.                            .___ .____                  
#|    |   \____\_ |__   ____  __ __  ____    __| _/ |    |    ____   ____  
#|    |   /    \| __ \ /  _ \|  |  \/    \  / __ |  |    |   /  _ \ / ___\ 
#|    |  /   |  \ \_\ (  <_> )  |  /   |  \/ /_/ |  |    |__(  <_> ) /_/  >
#|______/|___|  /___  /\____/|____/|___|  /\____ |  |_______ \____/\___  / 
#             \/    \/                  \/      \/          \/    /_____/  
## @juched - Process logs into SQLite3 for stats generation

## unbound_log.sh
######################################################################################
## - v1.0.0 - March 24 2020 - Initial version doing both nx_domains and reply_domains
## - v1.1.0 - April 05 2020 - Add support for tracking client IP
## - v1.2.0 - April 13 2020 - Added header and no errors if log doesn't exist
## - v1.3.0 - April 15 2020 - Support tracking an output of blocked sites via DNS Firewall, clean up to speed up
## - v1.4.0 - April 21 2020 - Support non syslog logs (/opt/var/lib/unbound/..)
## - v1.5.0 - April 24 2020 - Add support for log_reopen to fix bug for non-syslog users
## - v1.6.0 - June 09 2025  - Added "export PATH" statement to give built-in binaries higher priority 
##                            than their equivalent Entware binaries [Martinski W.]
## - v1.6.1 - June 30 2025  - Miscellaneous code improvements [Martinski W.]
######################################################################################
# Last Modified: 2025-Jun-30
#-------------------------------------------------

readonly SCRIPT_VERSION="v1.6.1"
readonly SCRIPT_NAME="unbound_log.sh"

# Give priority to built-in binaries #
export PATH="/bin:/usr/bin:/sbin:/usr/sbin:$PATH"

##----------------------------------------##
## Modified by Martinski W. [2025-Jun-30] ##
##----------------------------------------##
[ -f /opt/bin/sqlite3 ] && SQLITE3_PATH="/opt/bin/sqlite3" || SQLITE3_PATH="/usr/sbin/sqlite3"

readonly SHARE_TEMP_DIR="/opt/share/tmp"
TMPDIR="$SHARE_TEMP_DIR"
SQLITE_TMPDIR="$TMPDIR"
if [ ! -d "$SHARE_TEMP_DIR" ]
then
    mkdir -m 777 -p "$SHARE_TEMP_DIR" 
fi
export SQLITE_TMPDIR TMPDIR

TZ="$(cat /etc/TZ)"
export TZ

Say()
{ echo -e "$@" | logger -st "${SCRIPT_NAME}_$$" ; }

ScriptHeader()
{
	printf "\n"
	printf "##\n"
	printf "# ____ ___     ___.                            .___ .____                  \\n"
	printf "#|    |   \____\_ |__   ____  __ __  ____    __| _/ |    |    ____   ____  \\n"
	printf "#|    |   /    \| __ \ /  _ \|  |  \/    \  / __ |  |    |   /  _ \ / ___\ \\n"
	printf "#|    |  /   |  \ \_\ (  <_> )  |  /   |  \/ /_/ |  |    |__(  <_> ) /_/  >\\n"
	printf "#|______/|___|  /___  /\____/|____/|___|  /\____ |  |_______ \____/\___  / \\n"
	printf "#             \/    \/                  \/      \/          \/    /_____/  \\n"
	printf "## by @juched - Process logs into SQLite3 for stats generation - %s \n" "$SCRIPT_VERSION"
	printf "\n"
	printf "%s\n" "$SCRIPT_NAME"
}

ScriptHeader

# default to non-syslog location and variable positions #
unbound_logfile="/opt/var/lib/unbound/unbound.log"
n_reply_domain=7
n_reply_reply=10
n_reply_client_ip=6
n_nx_domain=6
n_rpz_domain=9
n_rpz_zone=8
n_rpz_client_ip=11

# if syslog control file exists for unbound, then change log location and variable positions #
if [ -f "/opt/etc/syslog-ng.d/unbound" ]
then
   unbound_logfile="/opt/var/log/unbound.log"
   n_reply_domain=9
   n_reply_reply=12
   n_reply_client_ip=8
   n_nx_domain=8
   n_rpz_domain=11
   n_rpz_zone=10
   n_rpz_client_ip=13
fi

echo "Logfile used is $unbound_logfile"

#other variables#
tempSQL="/tmp/unbound_log.sql"
ubDBASE_DIR="/opt/var/lib/unbound"
ubDBASE_LOG="${ubDBASE_DIR}/unbound_log.db"
dateString="$(date '+%F')"
###dateString="2020-03-22"
olddateString7="$(date -D %s -d $(( $(date +%s) - 7*86400)) '+%F')"
echo "Date used is $dateString (7 days ago is $olddateString7)"
olddateString30="$(date -D %s -d $(( $(date +%s) - 30*86400)) '+%F')"
echo "Date used is $dateString (30 days ago is $olddateString30)"

if [ ! -d "$ubDBASE_DIR" ]
then
    Say "**ERROR**: Database directory [$ubDBASE_DIR] NOT found. Exiting."
    exit 1
fi

#create table to track adblocked domains from log-local-actions if needed#
echo "Creating nx_domain table if needed..."
printf "CREATE TABLE IF NOT EXISTS [nx_domains] ([domain] VARCHAR(255) NOT NULL, [date] DATE NOT NULL, [count] INTEGER NOT NULL, PRIMARY KEY(domain,date));" | "$SQLITE3_PATH" "$ubDBASE_LOG"

#delete old records > 7 days ago#
echo "Deleting old nx_domain records older than 7 days..."
printf "DELETE FROM nx_domains WHERE date < '$olddateString7';" | "$SQLITE3_PATH" "$ubDBASE_LOG"

# create table to track replies from log-replies 'yes' #
echo "Creating reply_domain table if needed..."
printf "CREATE TABLE IF NOT EXISTS [reply_domains] ([domain] VARCHAR(255) NOT NULL, [date] DATE NOT NULL, [reply] VARCHAR(32), [client_ip] VARCHAR(16) NOT NULL, [count] INTEGER NOT NULL, PRIMARY KEY(domain,date,reply,client_ip));" | "$SQLITE3_PATH" "$ubDBASE_LOG"

#delete old records > 7 days ago#
echo "Deleting old reply_domain records older than 7 days..."
printf "DELETE FROM reply_domains WHERE date < '$olddateString7';" | "$SQLITE3_PATH" "$ubDBASE_LOG"

# create table to track DNS Firewall RPZ applied from rpz-log 'yes' #
echo "Creating rpz_events table if needed..."
printf "CREATE TABLE IF NOT EXISTS [rpz_events] ([domain] VARCHAR(255) NOT NULL, [zone] VARCHAR(255), [date] DATE NOT NULL, [client_ip] VARCHAR(16) NOT NULL, [count] INTEGER NOT NULL, PRIMARY KEY(domain,zone,date,client_ip));" | "$SQLITE3_PATH" "$ubDBASE_LOG"

#delete old records > 30 days ago#
echo "Deleting old rpz_events records older than 30 days..."
printf "DELETE FROM rpz_events WHERE date < '$olddateString30';" | "$SQLITE3_PATH" "$ubDBASE_LOG"


# Add to SQLite all reply domains (log-replies must be yes) #
if [ -f "$unbound_logfile" ]
then
   # process reply logs - for top daily replies table #
   echo "BEGIN;" > "$tempSQL"
   cat "$unbound_logfile" | awk -v vardate="$dateString" -v vardomain="$n_reply_domain" -v varreply="$n_reply_reply" -v varclient="$n_reply_client_ip" '/reply: [0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/{print "INSERT OR IGNORE INTO reply_domains ([domain],[date],[reply],[client_ip],[count]) VALUES (\x27" substr($vardomain, 1, length($vardomain)-1) "\x27, \x27" vardate "\x27, \x27" $varreply "\x27, \x27" $varclient "\x27, 0);\nUPDATE reply_domains SET count = count + 1 WHERE domain = \x27" substr($vardomain, 1, length($vardomain)-1)"\x27 AND reply = \x27" $varreply "\x27 AND date = \x27" vardate "\x27 AND client_ip = \x27" $varclient "\x27;"}' >> "$tempSQL"
   echo "COMMIT;" >> "$tempSQL"

   # log out the processed nodes #
   reply_domaincount="$(grep -c "reply: \([0-9]\{1,3\}\.\)\{3\}" "$unbound_logfile")"
   Say "Processed $reply_domaincount reply_domains..." 

   echo "Removing reply lines from log file..."
   sed -i '\~reply: \([0-9]\{1,3\}\.\)\{3\}[0-9]\{1,3\}~d' "$unbound_logfile"

   # if syslog-ng running, need to restart it so logging continues #
   ##OFF## if [ -f "/opt/etc/syslog-ng.d/unbound" ]; then killall -HUP syslog-ng; fi

   echo "Running SQLite to import new reply records..."
   "$SQLITE3_PATH" "$ubDBASE_LOG" < "$tempSQL"

   #cleanup#
   if [ -f "$tempSQL" ]; then rm -f "$tempSQL" ; fi

   # Add to SQLite all blocked domains (log-local-actions must be yes) #
   echo "BEGIN;" > "$tempSQL"
   cat "$unbound_logfile" | awk -v vardate="$dateString" -v vardomain="$n_nx_domain" '/always_nxdomain/{print "INSERT OR IGNORE INTO nx_domains ([domain],[date],[count]) VALUES (\x27" substr($vardomain, 1, length($vardomain)-1) "\x27, \x27" vardate "\x27, 0);\nUPDATE nx_domains SET count = count + 1 WHERE domain = \x27" substr($vardomain, 1, length($vardomain)-1) "\x27 AND date = \x27" vardate "\x27;"}' >> "$tempSQL"
   echo "COMMIT;" >> "$tempSQL"

   # log out the processed nodes #
   nxdomain_count="$(grep -c "always_nxdomain" "$unbound_logfile")"
   Say "Processed $nxdomain_count nx_domains..."

   echo "Removing always_nxdomain lines from log file..."
   sed -i '\~always_nxdomain~d' "$unbound_logfile"

   echo "Removing static/transparent lines from log file (for performance)..."
   sed -i '\~info: [a-zA-Z.]* static \([0-9]\{1,3\}\.\)\{3\}[0-9]\{1,3\}~d' "$unbound_logfile"
   sed -i '\~info: [a-zA-Z.]* transparent \([0-9]\{1,3\}\.\)\{3\}[0-9]\{1,3\}~d' "$unbound_logfile"

   # if syslog-ng running, need to restart it so logging continues
   ##OFF## if [ -f "/opt/etc/syslog-ng.d/unbound" ]; then killall -HUP syslog-ng; fi

   echo "Running SQLite to import new nx records..."
   "$SQLITE3_PATH" "$ubDBASE_LOG" < "$tempSQL"

   #cleanup
   if [ -f "$tempSQL" ]; then rm -f "$tempSQL" ; fi

   # Process DNS Firewall stats #
   echo "BEGIN;" > "$tempSQL"
   cat "$unbound_logfile" | awk -v vardate="$dateString" -v vardomain="$n_rpz_domain" -v varzone="$n_rpz_zone" -v varclient="$n_rpz_client_ip" '/info: RPZ applied /{print "INSERT OR IGNORE INTO rpz_events ([domain],[zone],[date],[client_ip],[count]) VALUES (\x27" substr($vardomain, 1, length($vardomain)-1) "\x27, \x27" substr($varzone, 2, length($varzone)-2) "\x27, \x27" vardate "\x27, \x27" substr($varclient, 1, index($varclient, "@")-1) "\x27,0);\nUPDATE rpz_events SET count = count + 1 WHERE domain = \x27" substr($vardomain, 1, length($vardomain)-1) "\x27 AND zone = \x27" substr($varzone, 2, length($varzone)-2) "\x27 AND date = \x27" vardate "\x27 AND client_ip = \x27" substr($varclient, 1, index($varclient, "@")-1) "\x27;"}' >> "$tempSQL"
   echo "COMMIT;" >> "$tempSQL"

   # log out the processed nodes #
   rpzevents_count="$(grep -c "info: RPZ applied" "$unbound_logfile")"
   Say "Processed $rpzevents_count RPZ events..."

   echo "Removing RPZ event lines from log file..."
   sed -i '\~info: RPZ applied~d' "$unbound_logfile"

   # if syslog-ng running, need to restart it so logging continues #
   if [ -f "/opt/etc/syslog-ng.d/unbound" ]; then 
       killall -HUP syslog-ng
   else
       unbound-control log_reopen
   fi

   echo "Running SQLite to import new rpz event records..."
   "$SQLITE3_PATH" "$ubDBASE_LOG" < "$tempSQL"

   #cleanup#
   if [ -f "$tempSQL" ]; then rm -f "$tempSQL" ; fi
fi

echo "All done!"
