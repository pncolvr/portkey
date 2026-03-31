#!/usr/bin/env bash

utils=$(echo "$0" | xargs realpath | xargs dirname)/_common.sh
source "$utils"

checkDependencies az jq
login

tenant_id="${AZ_TENANT_ID:-}"

n8n_sub="${N8N_SUBSCRIPTION_ID:-}"
n8n_rg="${N8N_RESOURCE_GROUP:-}"
n8n_nsg="${N8N_NSG_NAME:-}"

user="$(obtainUserName)"
prefix="ClientIPAddress_${user}"

# Optional whitelists (space-separated names; only first segment before - or . is matched)
if [ -n "${VM_WHITELIST:-}" ]; then
  vm_whitelist=()
  for p in $VM_WHITELIST; do vm_whitelist+=("$p"); done
fi
if [ -n "${SQL_WHITELIST:-}" ]; then
  sql_whitelist=()
  for p in $SQL_WHITELIST; do sql_whitelist+=("$p"); done
fi

in_vm_whitelist() {
  local name="$1"
  local first_segment="${name%%[-.]*}"
  for w in "${vm_whitelist[@]}"; do [[ "$w" == "$first_segment" ]] && return 0; done
  return 1
}
in_sql_whitelist() {
  local name="$1"
  local first_segment="${name%%[-.]*}"
  for w in "${sql_whitelist[@]}"; do [[ "$w" == "$first_segment" ]] && return 0; done
  return 1
}

echo "Listing firewall rules matching '${prefix}*'"

if [ -n "$n8n_sub" ] && [ -n "$n8n_rg" ] && [ -n "$n8n_nsg" ]; then
  echo "N8N: subscription=$n8n_sub, rg=$n8n_rg, nsg=$n8n_nsg"
  az account set --subscription "$n8n_sub" 2>/dev/null || echo "  failed to set subscription"
  rules=$(az network nsg rule list -g "$n8n_rg" --nsg-name "$n8n_nsg" -o json 2>/dev/null || echo "[]")
  echo "$rules" | jq -r --arg pfx "$prefix" '
    [ .[] | select(.name | startswith($pfx)) ] |
    if length==0 then "  (none)" else
      .[] | "  - \(.name) [\(.access) \(.direction) \(.protocol)] src=\(.sourceAddressPrefix // (.sourceAddressPrefixes|join(","))) dstPort=\(.destinationPortRange // (.destinationPortRanges|join(","))) priority=\(.priority)"
    end
  '
else
  echo "N8N: environment variables not set; skipping"
fi

subs=$(az account list --query "[?tenantId=='$tenant_id' && state=='Enabled' && starts_with(name, '$SUBSCRIPTION_PREFIX')].id" -o tsv 2>/dev/null)

# ---- VMs -> NSGs ----
for sub in $subs; do
  echo "Subscription: $sub"
  az account set --subscription "$sub" || { echo "  failed to set subscription"; continue; }

  vms=$(az vm list --query "[].{name:name,rg:resourceGroup}" -o tsv 2>/dev/null) || { echo "  failed to list VMs; skipping"; continue; }
  while read -r vm rg; do
    [ -z "$vm" ] && continue
    if [ -n "${vm_whitelist:-}" ] && ! in_vm_whitelist "$vm"; then
      echo "  VM: $vm (RG: $rg) not in whitelist; skipping"
      continue
    fi
    echo "  VM: $vm (RG: $rg)"

    nic_ids=$(az vm show -g "$rg" -n "$vm" --query "networkProfile.networkInterfaces[].id" -o tsv 2>/dev/null)
    declare -A seen_nsg
    for nic_id in $nic_ids; do
      nic_json=$(az network nic show --ids "$nic_id" -o json 2>/dev/null) || continue
      nsg_id=$(echo "$nic_json" | jq -r '.networkSecurityGroup.id // empty')

      if [ -z "$nsg_id" ]; then
        subnet_id=$(echo "$nic_json" | jq -r '.ipConfigurations[0].subnet.id // empty')
        [ -n "$subnet_id" ] && nsg_id=$(az network vnet subnet show --ids "$subnet_id" --query "networkSecurityGroup.id" -o tsv 2>/dev/null || true)
      fi
      [ -z "$nsg_id" ] && echo "    No NSG on NIC/subnet; skipping" && continue

      [[ -n "${seen_nsg[$nsg_id]:-}" ]] && continue
      seen_nsg[$nsg_id]=1

      nsg_name="${nsg_id##*/}"
      nsg_rg=$(echo "$nsg_id" | awk -F/ '{for(i=1;i<=NF;i++) if ($i=="resourceGroups"){print $(i+1); exit}}')
      if [ -z "$nsg_name" ] || [ -z "$nsg_rg" ]; then
        read -r nsg_name nsg_rg < <(az network nsg show --ids "$nsg_id" --query "[name, resourceGroup]" -o tsv 2>/dev/null || echo "  ")
      fi
      if [ -z "$nsg_name" ] || [ -z "$nsg_rg" ]; then
        echo "    Failed to resolve NSG from id: $nsg_id; skipping"
        continue
      fi

      echo "    NSG: $nsg_name (RG: $nsg_rg)"
      rules=$(az network nsg rule list -g "$nsg_rg" --nsg-name "$nsg_name" -o json 2>/dev/null || echo "[]")
      echo "$rules" | jq -r --arg pfx "$prefix" '
        [ .[] | select(.name | startswith($pfx)) ] |
        if length==0 then "      (none)" else
          .[] | "      - \(.name) [\(.access) \(.direction) \(.protocol)] src=\(.sourceAddressPrefix // (.sourceAddressPrefixes|join(","))) dstPort=\(.destinationPortRange // (.destinationPortRanges|join(","))) priority=\(.priority)"
        end
      '
    done
    unset seen_nsg
  done <<< "$vms"
done

# ---- SQL servers ----
for sub in $subs; do
  echo "Subscription: $sub"
  az account set --subscription "$sub" || { echo "  failed to set subscription"; continue; }

  servers=$(az sql server list --query "[].{name:name,rg:resourceGroup}" -o tsv 2>/dev/null) || { echo "  failed to list SQL servers; skipping"; continue; }
  while read -r server rg; do
    [ -z "$server" ] && continue
    if [ -n "${sql_whitelist:-}" ] && ! in_sql_whitelist "$server"; then
      echo "  SQL: $server (RG: $rg) not in whitelist; skipping"
      continue
    fi
    echo "  SQL: $server (RG: $rg)"

    rules=$(az sql server firewall-rule list -g "$rg" -s "$server" -o json 2>/dev/null || echo "[]")
    echo "$rules" | jq -r --arg pfx "$prefix" '
      [ .[] | select(.name | startswith($pfx)) ] |
      if length==0 then "    (none)" else
        .[] | "    - \(.name): \(.startIpAddress) - \(.endIpAddress)"
      end
    '
  done <<< "$servers"
done