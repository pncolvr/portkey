#!/usr/bin/env bash
utils=$(echo "$0" | xargs realpath | xargs dirname)/_common.sh
source "$utils"

tenant_id="$AZ_TENANT_ID"

if [ -n "${SQL_WHITELIST:-}" ]; then
  whitelist=()
  for p in $SQL_WHITELIST; do whitelist+=("$p"); done
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

in_whitelist() {
  local name="$1"
  for w in "${whitelist[@]}"; do
    [[ "$w" == "$name" ]] && return 0
  done
  return 1
}

checkDependencies az curl jq sha1sum

login

suffix=$(obtainUserName)

[ -z "$suffix" ] && echo "Unable to find username" && exit 1

firewall_rule_name="ClientIPAddress_${suffix}"

echo "Firewall rule name: $firewall_rule_name"


myIp=$(obtainIp)

[ -z "$myIp" ] && echo "failed to obtain public ip" && exit 1
echo "Public IP: $myIp"

subs=$(az account list --query "[?tenantId=='$tenant_id' && state=='Enabled' && (starts_with(name, '$SUBSCRIPTION_PREFIX'))].id" -o tsv    )
for sub in $subs; do
  echo "Subscription: $sub"
  az account set --subscription "$sub" || { echo "  failed to set subscription"; continue; }

  servers=$(az sql server list --query "[].{name:name,rg:resourceGroup}" -o tsv 2>/dev/null) || { echo "  failed to list SQL servers; skipping"; continue; }
  while read -r server rg; do
    [ -z "$server" ] && continue
    echo "  Server: $server (RG: $rg)"

    first_segment="${server%%[-.]*}"
    if ! in_whitelist "$first_segment"; then
      echo "    $server not in whitelist, continuing"
      continue
    fi

    existing=$(az sql server firewall-rule show -g "$rg" -s "$server" -n "$firewall_rule_name" -o json 2>/dev/null)
    if [ "$desired" = "on" ]; then
      if [ -n "$existing" ] && [ "$existing" != "null" ]; then
        start=$(echo "$existing" | jq -r '.startIpAddress')
        end=$(echo "$existing" | jq -r '.endIpAddress')
        if [ "$start" = "$myIp" ] && [ "$end" = "$myIp" ]; then
          echo "    Rule already set to $myIp -> nothing to do"
        else
          echo "    Setting rule to $myIp (enable)"
          az sql server firewall-rule update -g "$rg" -s "$server" -n "$firewall_rule_name" --start-ip-address "$myIp" --end-ip-address "$myIp" || \
            az sql server firewall-rule create -g "$rg" -s "$server" -n "$firewall_rule_name" --start-ip-address "$myIp" --end-ip-address "$myIp"
        fi
      else
        echo "    Rule not found -> creating with $myIp (enable)"
        az sql server firewall-rule create -g "$rg" -s "$server" -n "$firewall_rule_name" --start-ip-address "$myIp" --end-ip-address "$myIp" || echo "    create failed"
      fi
    else
      if [ -n "$existing" ] && [ "$existing" != "null" ]; then
        echo "    Deleting rule (disable)"
        az sql server firewall-rule delete -g "$rg" -s "$server" -n "$firewall_rule_name" || echo "    delete failed"
      else
        echo "    Rule not present -> nothing to do"
      fi
    fi
    done <<< "$servers"
done