# About

Bunch of scripts I hacked together at work to be able to access Azure resources from my location.
It updates firewall rules or network security group rules with the name and public IP of the logged in user.
This work is focused on virtual machines and SQL servers.

# Build
```
podman build -t portkey:latest -f Dockerfile .
podman compose up -d
```

# Run
## create volume if not using the compose file

```
podman volume create portkey-volume
```
```
podman run -d --name portkey \
  -v portkey-volume:/home/vscode/.azure \
  -v "<repo_path>":/workspaces/scripts/azure/portkey \
  -w /workspaces/scripts/azure/portkey \
  --restart=unless-stopped \
  portkey:latest sleep infinity
```

# Remove

```
podman kill -s KILL portkey
podman rm -f portkey
```

# On your bash profile, for convenience
```
function _ensure-container-running(){
  if ! podman inspect -f '{{.State.Running}}' "portkey" 2>/dev/null | grep -qx true; then
    portkey-container-start
  fi
}

function _exec-in-container() {
  _ensure-container-running
  podman exec -it portkey "$@"
}

alias portkey-container-stop='podman kill -s KILL portkey && podman rm -f portkey'

function portkey-container-start(){
  podman run -d --replace --name portkey \
    -v portkey-azure:/home/vscode/.azure \
    -v "/home/pncolvr/Projects/helpers/portkey":/workspaces/scripts/azure/portkey \
    -w /workspaces/scripts/azure/portkey \
    --restart=unless-stopped \
    portkey:latest sleep infinity
}

function portkey-n8n() {
  _exec-in-container /workspaces/scripts/azure/portkey/scripts/n8n-firewall-my-ip.sh "$@"
}

function portkey-sql() {
  _exec-in-container /workspaces/scripts/azure/portkey/scripts/sql-firewall-my-ip.sh "$@"
}

function portkey-vm() {
  _exec-in-container /workspaces/scripts/azure/portkey/scripts/vm-firewall-my-ip.sh "$@"
}

function portkey-list-rules() {
  _exec-in-container /workspaces/scripts/azure/portkey/scripts/list-my-rules.sh "$@"
}

function portkey-list-subs() {
  _exec-in-container /workspaces/scripts/azure/portkey/scripts/list-subs.sh "$@"
}
```