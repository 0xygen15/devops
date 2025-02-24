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

#Check if ufw is installed.
if command -v ufw &> /dev/null; then
    echo "Check: ufw is installed"
else
    echo "Installing ufw..."
    sudo apt install ufw 
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

#Enable IP forwarding
echo 'net.ipv4.ip_forward=1' > /etc/sysctl.d/99-openvpn.conf
sysctl --system

# Очистка существующих правил
iptables -F
iptables -X
iptables -t nat -F

# Установка базовой политики
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT ACCEPT

# Разрешение локального трафика
iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT

# Разрешение установленных соединений
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# Разрешение SSH (порт 22)
iptables -A INPUT -p tcp --dport 22 -j ACCEPT

# Разрешение OpenVPN (порт 1194 UDP)
iptables -A INPUT -p udp --dport 1194 -j ACCEPT

# Определение внешнего интерфейса
INTERFACE=$(ip -4 route ls | grep default | grep -Po '(?<=dev )(\S+)')

# Настройка NAT
iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -o $INTERFACE -j MASQUERADE

# Настройка форвардинга
iptables -A FORWARD -i tun0 -j ACCEPT
iptables -A FORWARD -i $INTERFACE -o tun0 -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A FORWARD -i tun0 -o $INTERFACE -j ACCEPT

sudo apt install iptables-persistent -y
netfilter-persistent save
netfilter-persistent reload

#Firewall settings
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh
ufw allow 1194/udp
ufw allow from 10.8.0.0/24

#Fowarding settings
echo 'net.ipv4.ip_forward=1' >> /etc/ufw/sysctl.conf
echo '*nat' >> /etc/ufw/before.rules
echo ':POSTROUTING ACCEPT [0:0]' >> /etc/ufw/before.rules
echo "-A POSTROUTING -s 10.8.0.0/24 -o ${INTERFACE} -j MASQUERADE" >> /etc/ufw/before.rules
echo 'COMMIT' >> /etc/ufw/before.rules

ufw enable
