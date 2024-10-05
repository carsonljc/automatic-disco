#!/bin/bash

# Function to display usage
usage() {
    echo "Usage: $0 --bucket <BUCKET_NAME> --object <OBJECT_NAME> --prefix <OUTLINE_PREFIX>"
    exit 1
}

# Parse command-line arguments
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --bucket) BUCKET_NAME="$2"; shift ;;
        --object) OBJECT_NAME="$2"; shift ;;
        --prefix) OUTLINE_PREFIX="$2"; shift ;;
        *) usage ;;
    esac
    shift
done

# Check if all required parameters are provided
if [[ -z "$BUCKET_NAME" || -z "$OBJECT_NAME" || -z "$OUTLINE_PREFIX" ]]; then
    usage
fi

# install dependencies
apt-get update
apt-get install jq -y

# Install Outline Server
curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
sudo sh /tmp/get-docker.sh
sudo bash -c "$(wget -qO- https://raw.githubusercontent.com/Jigsaw-Code/outline-server/master/src/server_manager/install_scripts/install_server.sh) --keys-port 443"

# Generate new default key
export API_URL=$(grep "apiUrl" /opt/outline/access.txt | cut -d: -f 2- | xargs)
curl --insecure -X DELETE "$API_URL/access-keys/default"
curl --insecure -X PUT "$API_URL/access-keys/default"

# Store the configs
curl --insecure -X GET "$API_URL/access-keys/default" | jq --arg prefix "$OUTLINE_PREFIX" '{ server: (.accessUrl | split("@")[1] | split(":")[0]), server_port: (.port), password: (.password), method: (.method), prefix: $prefix }' > /tmp/outline.json
curl --insecure -X GET "$API_URL/access-keys/default" | jq '{"version": 1, "servers": [{ server: (.accessUrl | split("@")[1] | split(":")[0]), server_port: (.port), password: (.password), method: (.method) }]}' > /tmp/shadowsocks.json

# Save configs to S3
aws s3api put-object --bucket "$BUCKET_NAME" --key "outline/$OBJECT_NAME" --body /tmp/outline.json --acl public-read
aws s3api put-object --bucket "$BUCKET_NAME" --key "shadowsocks/$OBJECT_NAME" --body /tmp/shadowsocks.json --acl public-read

# Set tcp congestion control
sudo sh -c 'echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf'
sudo sh -c 'echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf'
sysctl -p