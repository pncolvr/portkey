#!/usr/bin/env bash
utils=$(echo "$0" | xargs realpath | xargs dirname)/_common.sh
source "$utils"

checkDependencies az curl jq sha1sum fzf

tenant_id="$AZ_TENANT_ID"
subscription_id="$N8N_SUBSCRIPTION_ID"
resource_group="$N8N_RESOURCE_GROUP"
nsg_name="$N8N_NSG_NAME"

if [ -n "${N8N_PORTS:-}" ]; then
  ports=()
  for p in $N8N_PORTS; do ports+=("$p"); done
fi

if [ $# -eq 0 ]; then
  action=$(ask_for_option)
else
  action="${1,,}"
fi

case "$action" in
  on|true|enable|1) desired="on" ;;
  off|false|disable|0) desired="off" ;;
  *) echo "Invalid action '$1'. Use on|off|true|false." >&2; exit 1 ;;
esac


login

suffix=$(obtainUserName)

[ -z "$suffix" ] && echo "Unable to find username" && exit 1

myIp=$(obtainIp)

[ -z "$myIp" ] && echo "failed to obtain public ip" && exit 1

echo "Public IP: $myIp"

az account set --subscription "$subscription_id" || { echo "failed to set subscription"; exit 1; }

for i in "${!ports[@]}"; do
  manage_nsg_rule "$suffix" "$myIp" "$resource_group" "$nsg_name" "$desired" "${ports[$i]}" "$i"
done