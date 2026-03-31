#!/usr/bin/env bash
utils=$(echo "$0" | xargs realpath | xargs dirname)/_common.sh
source "$utils"

checkDependencies az curl jq fzf

tenant_id="$AZ_TENANT_ID"

if [ -n "${VM_WHITELIST:-}" ]; then
  whitelist=()
  for p in $VM_WHITELIST; do whitelist+=("$p"); done
fi

if [ -n "${VM_PORTS:-}" ]; then
  ports=()
  for p in $VM_PORTS; do ports+=("$p"); done
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
  # Derive first segment of name (before first '-' or '.')
  local first_segment="${name%%[-.]*}"
  for w in "${whitelist[@]}"; do
    [[ "$w" == "$first_segment" ]] && return 0
  done
  return 1
}

login

suffix=$(obtainUserName)

[ -z "$suffix" ] && echo "Unable to find username" && exit 1

myIp=$(obtainIp)

[ -z "$myIp" ] && echo "failed to obtain public ip" && exit 1

echo "Public IP: $myIp"

subs=$(az account list --query "[?tenantId=='$tenant_id' && state=='Enabled' && (starts_with(name, '$SUBSCRIPTION_PREFIX'))].id" -o tsv)
for sub in $subs; do
  echo "Subscription: $sub"
  az account set --subscription "$sub" || { echo "  failed to set subscription"; continue; }

  vms=$(az vm list --query "[].{name:name,rg:resourceGroup}" -o tsv 2>/dev/null) || { echo "  failed to list VMs; skipping"; continue; }
  while read -r vm rg; do
    [ -z "$vm" ] && continue

    if ! in_whitelist "$vm"; then
      echo "  VM: $vm (RG: $rg) not in whitelist, continuing"
      continue
    fi

    echo "  VM: $vm (RG: $rg)"

    nic_ids=$(az vm show -g "$rg" -n "$vm" --query "networkProfile.networkInterfaces[].id" -o tsv 2>/dev/null)
    if [ -z "$nic_ids" ]; then
      echo "    No NICs found; skipping"
      continue
    fi

    declare -A seen_nsg

    for nic_id in $nic_ids; do
      nic_json=$(az network nic show --ids "$nic_id" -o json 2>/dev/null) || continue
      nsg_id=$(echo "$nic_json" | jq -r '.networkSecurityGroup.id // empty')

      if [ -z "$nsg_id" ]; then
        subnet_id=$(echo "$nic_json" | jq -r '.ipConfigurations[0].subnet.id // empty')
        if [ -n "$subnet_id" ]; then
          nsg_id=$(az network vnet subnet show --ids "$subnet_id" --query "networkSecurityGroup.id" -o tsv 2>/dev/null || true)
        fi
      fi

      if [ -z "$nsg_id" ]; then
        echo "    No NSG associated with NIC or Subnet; skipping"
        continue
      fi

      # Skip duplicate NSGs per VM
      if [[ -n "${seen_nsg[$nsg_id]:-}" ]]; then
        continue
      fi
      seen_nsg[$nsg_id]=1

      nsg_name="${nsg_id##*/}"
      nsg_rg=$(echo "$nsg_id" | awk -F/ '{for(i=1;i<=NF;i++) if ($i=="resourceGroups"){print $(i+1); exit}}')

      if [ -z "$nsg_name" ] || [ -z "$nsg_rg" ]; then
        read -r nsg_name nsg_rg < <(az network nsg show --ids "$nsg_id" --query "[name, resourceGroup]" -o tsv 2>/dev/null || echo "  ")
      fi

      if [ -z "$nsg_name" ] || [ -z "$nsg_rg" ]; then
        echo "    Failed to resolve NSG name/RG from id: $nsg_id; skipping"
        continue
      fi

      echo "    NSG: $nsg_name (RG: $nsg_rg)"
      for i in "${!ports[@]}"; do
        manage_nsg_rule "$suffix" "$myIp" "$nsg_rg" "$nsg_name" "$desired" "${ports[$i]}" "$i"
      done
    done

    unset seen_nsg
  done <<< "$vms"
done
