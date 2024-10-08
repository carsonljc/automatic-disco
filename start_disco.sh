#!/bin/bash

# Function to display usage
usage() {
    echo "Usage: $0 --prefix <OUTLINE_PREFIX>"
    exit 1
}

# Parse command-line arguments
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --prefix) OUTLINE_PREFIX="$2"; shift ;;
        *) usage ;;
    esac
    shift
done

# Check if all required parameters are provided
if [[-z "$OUTLINE_PREFIX" ]]; then
    usage
fi

# install dependencies
apt-get update
apt-get install jq -y

# Install Outline Server
sudo bash -c "$(wget -qO- https://raw.githubusercontent.com/Jigsaw-Code/outline-server/master/src/server_manager/install_scripts/install_server.sh) --keys-port 443"

export API_URL=$(grep "apiUrl" /opt/outline/access.txt | cut -d: -f 2- | xargs)

# Declare an associative array to map IDs to their byte limits in GB
declare -A keys_limits
keys_limits=(
    ["personal"]=1000  # 1 TB = 1000 GB
    ["sk"]=100    # 100 GB
)

# Loop through the keys
for id in "${!keys_limits[@]}"; do
    limit=$((keys_limits[$id] * 1000000000))  # Convert GB to bytes

    # Generate new key
    curl --insecure -X DELETE "$API_URL/access-keys/$id"
    curl --insecure -X PUT "$API_URL/access-keys/$id"
    curl --insecure -X PUT "$API_URL/access-keys/$id/data-limit" -H "Content-Type: application/json" -d "{\"limit\": {\"bytes\": $limit}}"

    # Store the configs for each key
    curl --insecure -X GET "$API_URL/access-keys/$id" | jq --arg prefix "$OUTLINE_PREFIX" '{ server: (.accessUrl | split("@")[1] | split(":")[0]), server_port: (.port), password: (.password), method: (.method), prefix: $prefix }' > "/tmp/${id}_outline.json"
    curl --insecure -X GET "$API_URL/access-keys/$id" | jq '{"version": 1, "servers": [{ server: (.accessUrl | split("@")[1] | split(":")[0]), server_port: (.port), password: (.password), method: (.method) }]}' > "/tmp/${id}_shadowsocks.json"
done

# Set tcp congestion control
sudo sh -c 'echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf'
sudo sh -c 'echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf'
sysctl -p