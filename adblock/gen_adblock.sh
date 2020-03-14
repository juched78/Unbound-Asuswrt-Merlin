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
# @juched - v1.0.4
# 	Special thanks to @Martineau @rgnldo @Jack_Yaz for setting up and hosting and thinking of this
# v1.0.1 - moved config to /opt/share/unbound/configs
#	 - save and reload unbound cache on restart
# v1.0.2 - separated required domains from user editable domains for allow list
# v1.0.3 - switched to use unbound_manager.sh restart to be more safe
# v1.0.4 - cleanup and split of sites file by jumpsmm7 (Thank you!)

destinationIP="0.0.0.0"

#adblock function paths
tempoutlist="/opt/var/lib/unbound/adblock/adlist"
tempwhitelistoutlist="/opt/var/lib/unbound/adblock/whitelist"
outlist='/opt/var/lib/unbound/adblock/outlist'
finalist='/opt/var/lib/unbound/adblock/finalist'
permlist='/opt/var/lib/unbound/adblock/permlist'
adlist='/opt/var/lib/unbound/adblock/adservers'

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

# check for sites file
if [ ! -f $blocksites ]; then
  logger -st "($(basename $0))" "Missing $blocksites file"
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
  echo "Attempting to Download $count of $(wc -l < $sites) from $url."
  # legacy curl --progress-bar $url | grep -v "#" | grep -v "::1" | grep -v "0.0.0.0 0.0.0.0" | sed '/^$/d' | sed 's/\ /\\ /g' | awk '{print $NF}' | grep -v '^\\' | grep -v '\\$'| sort >> $list
  curl --progress-bar $url | grep -o '^[^#]*' | grep -v "::1" | grep -v "0.0.0.0 0.0.0.0" | sed '/^$/d' | sed 's/\ /\\ /g' | awk '{print $NF}' | grep -o '^[^\\]*' | grep -o '^[^\\$]*' | sort >> $list
  dos2unix $list
  done
  count=$((count + 1))
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

download_file $blocksites $tempoutlist
[ -f $allowsites ] && echo "Downloading User Allow List..." && download_file $allowsites $tempwhitelistoutlist
[ -f $blocklist ] && echo "Combining User Custom block host..." && cat $blocklist >> $tempoutlist
[ -f $tempwhitelistoutlist ] && echo "Removing any downloaded whitelist items..." && filter_file $tempwhitelistoutlist $tempoutlist
[ -f $allowlist ] && echo "Filtering user requested domains from adblock list..." && filter_file $allowlist $tempoutlist
[ -f $permlist ] && echo "Filtering required domains from adblock list..." && filter_file $permlist $tempoutlist
[ -f $tempoutlist ] && echo "Removing unnecessary formatting from the domain list..." && cleanup $tempoutlist $outlist $finalist
numberOfAdsBlocked=$(wc -l < $outlist)
echo "$numberOfAdsBlocked domains compiled"
echo "Generating Unbound adlist....."
awk '{print "local-zone: \""$1"\" always_nxdomain"}' $finalist > $adlist
numberOfAdsBlocked=$(wc -l < $adlist)
echo " Number of adblocked (ads/malware/tracker) and blacklisted domains: $numberOfAdsBlocked" > $statsFile
echo " Last updated: $(date +"%c")" >> $statsFile

echo "Removing temporary files..."
[ -f $tempoutlist ] && rm -f $tempoutlist
[ -f $tempwhitelistoutlist ] && rm -f $tempwhitelistoutlist
[ -f $outlist ] && rm -f $outlist
[ -f $finalist ] && rm -f $finalist

echo "Restarting Unbound DNS server..."
/jffs/addons/unbound/unbound_manager.sh restart
echo "Adblock update complete!"
