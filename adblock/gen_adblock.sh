#!/bin/bash

# AdBlock Script to download from customizable lists and merge into unbound rules file.
# Use permlist file in same folder to add per line domains you want to whitelist.
# Use blocklist file in same folder to block per line domains you want to block.
# Use blocksites file to create list of sites/URLs you want to download for blocklist.
# Use allowsites file to create list of sites/URLs you want to download for whitelist.
# File is in the format of 1 site/URL per line with two lists.
#	<URL>
# list format can be one of any:
#		domains - for lists of the format of 1 domain per line
#		hosts - for lists of the format of 1 host file entry per line with 0.0.0.0 IP (sorry, no 127.0.0.1)
# @juched
# 	Special thanks to @Martineau @rgnldo @Jack_Yaz for setting up and hosting and thinking of this
# v1.0.1 - moved config to /opt/share/unbound/configs
#	 - save and reload unbound cache on restart
# v1.0.2 - separated required domains from user editable domains for allow list
# v1.0.3 - switched to use unbound_manager.sh restart to be more safe
# v1.0.4 - cleanup and split of sites file by jumpsmm7 (Thank you!)
# v1.0.5 - Output version header, add count of file processed, and support files with comments AFTER the domain (thanks jumpsmm7)
# v1.0.6 - Outout to logger as well, swich to reload command, skip commented out download lines, update adblock with using restart or reload
# v1.0.7 - Fixed issue without count of URLs displayed when some are commented out
# v1.0.8 - Added support for .zone files.  Filename must end in .zone

Say(){
   echo -e $$ $@  | logger -st "($(basename $0))"
}

echo "                             "
echo " _____   _ _   _         _   "
echo "|  _  |_| | |_| |___ ___| |_ "
echo "|     | . | . | | . |  _| '_|"
echo "|__|__|___|___|_|___|___|_,_|"
Say " @juched - v1.0.8 - Thanks to @SomeWhereOverTheRainBow"
echo ""
                             
#adblock function paths
tempoutlist="/opt/var/lib/unbound/adblock/adlist"
tempwhitelistoutlist="/opt/var/lib/unbound/adblock/whitelist"
outlist='/opt/var/lib/unbound/adblock/outlist'
finalist='/opt/var/lib/unbound/adblock/finalist'
permlist='/opt/var/lib/unbound/adblock/permlist'
adlist='/opt/var/lib/unbound/adblock/adservers'
loadlist='/opt/var/lib/unbound/adblock/loadservers'
unloadlist='/opt/var/lib/unbound/adblock/unloadservers'

#user settings paths
blocklist='/opt/share/unbound/configs/blockhost'
allowlist='/opt/share/unbound/configs/allowhost'
blocksites='/opt/share/unbound/configs/blocksites'
allowsites='/opt/share/unbound/configs/allowsites'
#used to write out stats in case people want to see
statsFile="/opt/var/lib/unbound/adblock/stats.txt"

echo "Removing possible temporary files.."
[ -f $tempoutlist ] && rm -f $tempoutlist
[ -f $tempwhitelistoutlist ] && rm -f $tempwhitelistoutlist
[ -f $outlist ] && rm -f $outlist
[ -f $finalist ] && rm -f $finalist
[ -f $unloadlist ] && rm -f $unloadlist
[ -f $loadlist ] && rm -f $loadlist

# check for sites file
if [ ! -f $blocksites ]; then
  Say "Missing $blocksites file"
  exit
fi

# process blocksites list
download_file () {
  sites=$1
  list=$2
  count=1
  while read -r line
  do
    set -- $line
    for url in $(echo $line); do
      [ "${url:0:1}" == "#" ] && continue # skip commented out lines - Thanks @Martineau
      echo "Attempting to Download $count of $(awk 'NF && !/^[:space:]*#/' $sites | wc -l) from $url."
      if [ "${url##*.}" == "zone" ];then
        curl --progress-bar $url | sed -rn 's/^local-zone: "(.*)".*$/\1/p' | sort >> $list
      else
        curl --progress-bar $url | grep -o '^[^#]*' | grep -v "::1" | grep -v "0.0.0.0 0.0.0.0" | sed '/^$/d' | sed 's/\ /\\ /g' | awk '{print tolower($NF)}' | grep -o '^[^\\]*' | grep -o '^[^\\$]*' | sort >> $list
      fi
      dos2unix $list
      count=$((count + 1))
    done
  done < "$sites"
}

filter_file () {
  filter=$1
  original=$2
  if [ "$(wc -l < $filter)" -ne "0" ]; then
    awk 'NR==FNR{a[$0];next} !($0 in a) {print $NF}' $filter $original | sort -u > ${original}.tmp
    mv ${original}.tmp $original
  else
    echo "No filtering from $filter required for $original..."
  fi
}

cleanup () { 
  unclean=$1
  output=$2
  grep -oE "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b" $unclean | sort -u > ${output}.tmp
  if [ "$(wc -l < ${output}.tmp)" -ne "0" ]; then
    mv ${output}.tmp $output
    awk 'NR==FNR{a[$0];next} !($0 in a) {print $NF}' $output $unclean | sort -u > ${output}.tmp
    mv ${output}.tmp $output
  else
    rm -rf ${output}.tmp
    mv $unclean $output
  fi
  cat $output | sed -r -e 's/[[:space:]]+/\t/g' | sed -e 's/\t*#.*$//g' | sed -e 's/[^a-zA-Z0-9\.\_\t\-]//g' | sed -e 's/\t$//g' | sed -e '/^#/d' | sed -e 's/^[ \t]*//;s/[ \t]*$//' | sort -u | sed '/^$/d' > $3
}

echo "Downloading list(s) from block site(s) configured..."
download_file $blocksites $tempoutlist
[ -f $allowsites ] && echo "Downloading list(s) from allow site(s) configured..." && download_file $allowsites $tempwhitelistoutlist
[ -f $blocklist ] && echo "Adding user requested hosts to list..." && cat $blocklist >> $tempoutlist
[ -f $tempwhitelistoutlist ] && echo "Removing allow list downloaded whitelist hosts from list..." && filter_file $tempwhitelistoutlist $tempoutlist
[ -f $allowlist ] && echo "Removing user requested hosts from list..." && filter_file $allowlist $tempoutlist
[ -f $permlist ] && echo "Removing required hosts from list..." && filter_file $permlist $tempoutlist
[ -f $tempoutlist ] && echo "Removing unnecessary formatting from the domain list..." && cleanup $tempoutlist $outlist $finalist

echo "Generating Unbound adservers file..."
sed -i '/\.\.\./d' $finalist
awk '{print "local-zone: \""$1"\" always_nxdomain"}' $finalist > $adlist
numberOfHostsBlocked=$(wc -l < $adlist)
Say "Number of adblocked hosts: $numberOfHostsBlocked"
echo " Number of adblocked (ads/malware/tracker) and blacklisted hosts: $numberOfHostsBlocked" > $statsFile
echo " Last updated: $(date +"%c")" >> $statsFile

if [ -n "$(pidof unbound)" ];then
  echo "Generating Unbound unload/load lists..."
  unbound-control list_local_zones | grep "always_nxdomain" | grep -v "use-application-dns.net" | awk '{print ""$1""}' > $unloadlist
  awk '{print ""$1" always_nxdomain"}' $finalist > $loadlist

  echo "Loading/Unload Unbound local-zones to take effect..."
  [ -f $unloadlist ] && unbound-control local_zones_remove < $unloadlist
  [ -f $loadlist ] && unbound-control local_zones < $loadlist
else
  Say "Warning unbound NOT running!"
fi 

echo "Removing temporary files..."
[ -f $tempoutlist ] && rm -f $tempoutlist
[ -f $tempwhitelistoutlist ] && rm -f $tempwhitelistoutlist
[ -f $outlist ] && rm -f $outlist
[ -f $finalist ] && rm -f $finalist
[ -f $unloadlist ] && rm -f $unloadlist
[ -f $loadlist ] && rm -f $loadlist

echo "Adblock update complete!"
