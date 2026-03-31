#!/usr/bin/env bash

checkDependencies() {
    printf "Checking dependencies... "
    missingDependencies=0
    for name in "$@"; do
        if ! which "$name" 1>/dev/null 2>/dev/null; then
            printf "\n\t%s needs to be installed." "$name"
            missingDependencies=1
        fi
    done
    if [ $missingDependencies -ne 1 ]; then
        printf "OK\n"
    else
        printf "\nInstall the above and rerun this script"
        exit 1
    fi
}

obtainIp() {
    for url in "https://api.ipify.org" "https://ipv4.icanhazip.com"; do
        ip=$(curl -s -4 "$url" | tr -d '[:space:]')
        [[ $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] && echo "$ip" && break
    done
}

obtainUserName() {
    upn=$(az account show --query "user.name" -o tsv 2>/dev/null)
    local_part=${upn%@*}

    suffix=$(
    echo "${local_part:-$upn}" | awk '{
        n=split(tolower($0), a, /[^[:alnum:]]+/);
        for (i=1; i<=n; i++) if (length(a[i])) {printf toupper(substr(a[i],1,1)) substr(a[i],2)}
    }'
    )
    echo "$suffix"
}

login(){
    tenant_id="$AZ_TENANT_ID"
    current_tenant=$(az account show --query tenantId -o tsv 2>/dev/null || true)
    if ! az account get-access-token >/dev/null 2>&1 || [ "$current_tenant" != "$tenant_id" ]; then
        echo "Requesting login"
        az login --tenant "$tenant_id" --use-device-code || exit 1
    else
        echo "Not requesting login"
    fi
}

manage_nsg_rule() {
  local suffix="$1"
  local ip="$2"
  local resource_group="$3"
  local nsg_name="$4"
  local desired="$5"
  local port="$6"
  local idx="${7:-0}"
  # # Derive a stable priority from suffix+port to avoid collisions without listing rules
  # local base_priority=$((3500 + idx))
  local firewall_rule_name="ClientIPAddress_${suffix}_${port}"

  echo "      Firewall rule name: $firewall_rule_name"

  local existing
  existing=$(az network nsg rule show -g "$resource_group" --nsg-name "$nsg_name" -n "$firewall_rule_name" -o json 2>/dev/null)

  local priority
  if [ -n "$existing" ] && [ "$existing" != "null" ]; then
    priority=$(echo "$existing" | jq -r '.priority // empty')
  fi
  if [ -z "$priority" ] || [ "$priority" = "null" ]; then
    local key hash_hex hash_dec
    key="${suffix}-${port}"
    hash_hex=$(printf "%s" "$key" | sha1sum | awk '{print $1}')
    hash_dec=$((16#${hash_hex:0:6}))
    priority=$(( 100 + ((hash_dec + idx) % 3997) ))
  fi

  if [ "$desired" = "on" ]; then
    if [ -n "$existing" ] && [ "$existing" != "null" ]; then
      local prefix dport proto dir acc
      prefix=$(echo "$existing" | jq -r '.sourceAddressPrefix // (.sourceAddressPrefixes[0] // "")')
      dport=$(echo "$existing" | jq -r '.destinationPortRange // (.destinationPortRanges[0] // "")')
      proto=$(echo "$existing" | jq -r '.protocol')
      dir=$(echo "$existing" | jq -r '.direction')
      acc=$(echo "$existing" | jq -r '.access')
      if [ "$prefix" = "$ip" ] && [ "$dport" = "$port" ] && [ "$proto" = "Tcp" ] && [ "$dir" = "Inbound" ] && [ "$acc" = "Allow" ]; then
        echo "      Rule already set to $ip for TCP $port -> nothing to do"
      else
        echo "      Setting rule to $ip for TCP $port (enable)"
        az network nsg rule update -g "$resource_group" --nsg-name "$nsg_name" -n "$firewall_rule_name" \
          --access Allow --direction Inbound --protocol Tcp \
          --source-address-prefixes "$ip" --destination-port-ranges "$port" \
          --priority "$priority" || \
        az network nsg rule create -g "$resource_group" --nsg-name "$nsg_name" -n "$firewall_rule_name" \
          --access Allow --direction Inbound --protocol Tcp \
          --source-address-prefixes "$ip" --destination-port-ranges "$port" \
          --priority "$priority"
      fi
    else
      echo "      Rule not found -> creating with $ip for TCP $port (enable)"
      az network nsg rule create -g "$resource_group" --nsg-name "$nsg_name" -n "$firewall_rule_name" \
        --access Allow --direction Inbound --protocol Tcp \
        --source-address-prefixes "$ip" --destination-port-ranges "$port" \
        --priority "$priority" || echo "      create failed"
    fi
  else
    if [ -n "$existing" ] && [ "$existing" != "null" ]; then
      echo "      Deleting rule (disable)"
      az network nsg rule delete -g "$resource_group" --nsg-name "$nsg_name" -n "$firewall_rule_name" || echo "      delete failed"
    else
      echo "      Rule not present -> nothing to do"
    fi
  fi
}

function ask_for_option() {
  printf "on\noff" | fzf --header="what to do?" --prompt="> " --border --exit-0
}