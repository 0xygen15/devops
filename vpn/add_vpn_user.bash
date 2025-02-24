#!/bin/bash

if ! command -v curl &> /dev/null; then
  echo "Error: curl is not installed."
  echo "Installing ..."
  sudo apt install curl
else
  echo "Check: curl is available, proceeding ..."
fi

# Check if username is provided
if [ -z "$1" ]; then
  echo "Usage: $0 <username>"
  exit 1
fi

USERNAME="$1"
EASYRSA_DIR="/etc/openvpn/server/easy-rsa"
CLIENT_DIR="/etc/openvpn/client"
SERVER_IP=$(curl -s ipconfig.me)

# Generate client keys
cd "$EASYRSA_DIR" || exit
./easyrsa gen-req "$USERNAME" nopass
./easyrsa sign-req client "$USERNAME"

# Create client configuration directory if not exists
mkdir -p "$CLIENT_DIR"

# Create client .ovpn file
cat > "$CLIENT_DIR/${USERNAME}.ovpn" << EOF
client
dev tun
proto udp
remote $SERVER_IP 1194
resolv-retry infinite
nobind
persist-key
persist-tun
remote-cert-tls server
cipher AES-256-GCM
auth SHA256
key-direction 1
verb 3
EOF

# Append certificates and keys
echo "<ca>" >> "$CLIENT_DIR/${USERNAME}.ovpn"
cat pki/ca.crt >> "$CLIENT_DIR/${USERNAME}.ovpn"
echo "</ca>" >> "$CLIENT_DIR/${USERNAME}.ovpn"

echo "<cert>" >> "$CLIENT_DIR/${USERNAME}.ovpn"
cat "pki/issued/${USERNAME}.crt" >> "$CLIENT_DIR/${USERNAME}.ovpn"
echo "</cert>" >> "$CLIENT_DIR/${USERNAME}.ovpn"

echo "<key>" >> "$CLIENT_DIR/${USERNAME}.ovpn"
cat "pki/private/${USERNAME}.key" >> "$CLIENT_DIR/${USERNAME}.ovpn"
echo "</key>" >> "$CLIENT_DIR/${USERNAME}.ovpn"

echo "<tls-auth>" >> "$CLIENT_DIR/${USERNAME}.ovpn"
cat ta.key >> "$CLIENT_DIR/${USERNAME}.ovpn"
echo "</tls-auth>" >> "$CLIENT_DIR/${USERNAME}.ovpn"

echo "Client configuration for $USERNAME has been created: $CLIENT_DIR/${USERNAME}.ovpn"
