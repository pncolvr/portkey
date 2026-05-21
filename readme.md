# About

Bunch of scripts I hacked together at work to be able to access Azure resources from my location.
It updates firewall rules or network security group rules with the name and public IP of the logged in user.
This work is focused on virtual machines and SQL servers.

# Build
```
docker build -t portkey:latest -f Dockerfile .
docker compose up -d
```

# Run
## create volume if not using the compose file

```sh
docker volume create portkey-volume
```
```sh
docker run -d --name portkey \
  -v portkey-volume:/home/vscode/.azure \
  -v "<repo_path>":/workspaces/scripts/azure/portkey \
  -w /workspaces/scripts/azure/portkey \
  --restart=unless-stopped \
  portkey:latest sleep infinity
```

# Remove

```sh
docker kill -s KILL portkey
docker rm -f portkey
```

# On your bash profile, for convenience
```sh
function _ensure-container-running(){
  if ! docker inspect -f '{{.State.Running}}' "portkey" 2>/dev/null | grep -qx true; then
    portkey-container-start
  fi
}

function _exec-in-container() {
  _ensure-container-running
  docker exec -it portkey "$@"
}

alias portkey-container-stop='docker kill -s KILL portkey && docker rm -f portkey'

function portkey-container-start(){
  docker start portkey
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