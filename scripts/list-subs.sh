#!/usr/bin/env bash

utils=$(echo "$0" | xargs realpath | xargs dirname)/_common.sh
source "$utils"

checkDependencies az jq
login

az account list --query "[?tenantId=='$AZ_TENANT_ID' && state=='Enabled' && starts_with(name, '$SUBSCRIPTION_PREFIX')]" -o json