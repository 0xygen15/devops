# Step 1: Initial checks

#Ensure script runs as root.
if [[ $EUID -ne 0 ]]; then
    echo "Please this script run as root"
    exit 1
fi

#Check if OpenVPN is installed.
if command -v openvpn &> /dev/null; then
    echo "OpenVPN is already installed! Deleting and reinstalling ..."
    sudo reinstall openvpn
else
    echo "OpenVPN is not installed"
fi

#Check if port 1194 is in use.
if ss -tuln | grep -q ":1194"; then
    echo "Port 1194 is already in use!"
    exit 1
else
    echo "Port 1194 is free to be used."
fi

# Step 2: Install dependencies.

sudo apt update && sudo apt upgrade -y
sudo apt install openvpn easy-rsa -y

mkdir -p /etc/openvpn/server/certs
cd /etc/openvpn/server
cp -r /usr/share/easy-rsa .
cd easy-rsa

./easyrsa init-pki
./easyrsa build-ca nopass
./easyrsa gen-req server nopass
./easyrsa sign-req server server
./easyrsa gen-dh
openvpn --genkey secret ta.key

cat > /etc/openvpn/server/server.conf << EOF
port 1194
proto udp
dev tun
ca easy-rsa/pki/ca.crt
cert easy-rsa/pki/issued/server.crt
key easy-rsa/pki/private/server.key
dh easy-rsa/pki/dh.pem
tls-auth easy-rsa/ta.key 0
server 10.8.0.0 255.255.255.0
push "redirect-gateway def1 bypass-dhcp"
push "dhcp-option DNS 8.8.8.8"
push "dhcp-option DNS 8.8.4.4"
keepalive 10 120
cipher AES-256-GCM
auth SHA256
user nobody
group nogroup
persist-key
persist-tun
status openvpn-status.log
verb 3
EOF







