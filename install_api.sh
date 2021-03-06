#!/bin/bash
# install.sh
# Installs Helium masternode on Ubuntu 16.04 LTS x64

cd /root/

# retrieve name for config file which should have been dropped on server via API. Will be used for status feedback
# hname=$(<vpshostname.info)
# hname="testhostname"
hname=$(</root/installtemp/vpshostname.info)

#send status. Wil do this often. better to categorize tasks into maybe 5-6 , and send status for each instead of for every command run
curl -X POST https://www.heliumstats.online/code-red/status.php -H 'Content-Type: application/json-rpc' -d '{"hostname":"'"$hname"'","message": "Commencing installation script..."}'

# Changing the SSH Port to a custom number is a good security measure against DDOS attacks

_sshPortNumber=${VARIABLE:-22}

# Get a new privatekey by going to console >> debug and typing helium genkey

_nodePrivateKey="7RQ7eFVRxFMWfuAXS3jq6Q8pUkbTTVBjB7Xmf3Gfmj8cBZihJbU"

# The RPC node will only accept connections from your localhost
_rpcUserName=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 12 ; echo '')

# Choose a random and secure password for the RPC
_rpcPassword=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 32 ; echo '')

# Get the IP address of your vps which will be hosting the helium
_nodeIpAddress=$(ip route get 1 | awk '{print $NF;exit}')

# Set the connection port
_p2pport=':9009'

#send status
curl -X POST https://www.heliumstats.online/code-red/status.php -H 'Content-Type: application/json-rpc' -d '{"hostname":"'"$hname"'","message": "Checking for swap file ..."}'
# Check for swap file - if none, create one
if free | awk '/^Swap:/ {exit !$2}'; then
    echo ""
else
    fallocate -l 1G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile && cp /etc/fstab /etc/fstab.bak && echo '/swapfile none swap sw 0 0' | tee -a /etc/fstab
fi

# Make a new directory for helium daemon
mkdir ~/.helium/
touch ~/.helium/helium.conf

# Change the directory to ~/.helium
cd ~/.helium/

#send status
curl -X POST https://www.heliumstats.online/code-red/status.php -H 'Content-Type: application/json-rpc' -d '{"hostname":"'"$hname"'","message": "Generating MN config file..."}'
# Create the initial helium.conf file
echo "rpcuser=${_rpcUserName}
rpcpassword=${_rpcPassword}
rpcallowip=127.0.0.1
listen=1
server=1
daemon=1
logtimestamps=1
maxconnections=64
masternode=1
externalip=${_nodeIpAddress}
bind=${_nodeIpAddress}
masternodeaddr=${_nodeIpAddress}${_p2pport}
masternodeprivkey=${_nodePrivateKey}
" > helium.conf

cd /root/

#send status
curl -X POST https://www.heliumstats.online/code-red/status.php -H 'Content-Type: application/json-rpc' -d '{"hostname":"'"$hname"'","message": "Installing heliumd..."}'
# Install heliumd
set -e
git clone https://github.com/heliumchain/helium
cd helium
apt-get update -y && apt-get upgrade -y
apt-get install automake -y
add-apt-repository ppa:bitcoin/bitcoin -y
apt-get update -y
apt-get install build-essential libtool autotools-dev autoconf pkg-config libssl-dev libevent-dev libboost-all-dev  libprotobuf-dev protobuf-compiler  libdb4.8-dev libdb4.8++-dev -y
./autogen.sh
./configure  --disable-tests
make
make install
cd src
./heliumd -daemon

cd /root/

# Create a directory for helium's cronjobs
if [ -d ~/heliumnode ]; then
    rm -r ~/heliumnode
fi
mkdir heliumnode

# Change the directory to ~/heliumnode/
cd ~/heliumnode/

#send status
curl -X POST https://www.heliumstats.online/code-red/status.php -H 'Content-Type: application/json-rpc' -d '{"hostname":"'"$hname"'","message": "Downoading and installing monitoring scripts.."}'
# Download the appropriate scripts
wget https://raw.githubusercontent.com/cryptotronxyz/heliumnode/master/makerun.sh
wget https://raw.githubusercontent.com/cryptotronxyz/heliumnode/master/checkdaemon.sh
wget https://raw.githubusercontent.com/cryptotronxyz/heliumnode/master/clearlog.sh
wget https://raw.githubusercontent.com/cryptotronxyz/heliumnode/master/postinstall_api.sh

#send status
curl -X POST https://www.heliumstats.online/code-red/status.php -H 'Content-Type: application/json-rpc' -d '{"hostname":"'"$hname"'","message": "Creating cron jobs for monitoring..."}'

# Create a cronjob for making sure heliumd runs after reboot
#if ! crontab -l | grep "@reboot ~/helium/src/heliumd -daemon"; then
  (crontab -l ; echo "@reboot ~/helium/src/heliumd -daemon") | crontab -
#fi

# Create a cronjob for making sure heliumd is always running
#if ! crontab -l | grep "~/heliumnode/makerun.sh"; then
  (crontab -l ; echo "*/5 * * * * ~/heliumnode/makerun.sh") | crontab -
#fi

# Create a cronjob for making sure the daemon is never stuck
#if ! crontab -l | grep "~/heliumnode/checkdaemon.sh"; then
  (crontab -l ; echo "*/30 * * * * ~/heliumnode/checkdaemon.sh") | crontab -
#fi

# Create a cronjob for clearing the log file
#if ! crontab -l | grep "~/heliumnode/clearlog.sh"; then
  (crontab -l ; echo "0 0 */2 * * ~/heliumnode/clearlog.sh") | crontab -
#fi

# reboot logic for status feedback
(crontab -l ; echo "*/1 * * * * ~/heliumnode/postinstall_api.sh") | crontab -

# Give execute permission to the cron scripts
chmod 0700 ./makerun.sh
chmod 0700 ./checkdaemon.sh
chmod 0700 ./clearlog.sh
chmod 0700 ./postinstall_api.sh

#send status
curl -X POST https://www.heliumstats.online/code-red/status.php -H 'Content-Type: application/json-rpc' -d '{"hostname":"'"$hname"'","message": "Configuring ssh and enabling firewall..."}'
# Change the SSH port
sed -i "s/[#]\{0,1\}[ ]\{0,1\}Port [0-9]\{2,\}/Port ${_sshPortNumber}/g" /etc/ssh/sshd_config

# Firewall security measures
apt install ufw -y
ufw disable
ufw allow 9009
ufw allow "$_sshPortNumber"/tcp
ufw limit "$_sshPortNumber"/tcp
ufw logging on
ufw default deny incoming
ufw default allow outgoing
ufw --force enable

# Reboot the server
#send status
curl -X POST https://www.heliumstats.online/code-red/status.php -H 'Content-Type: application/json-rpc' -d '{"hostname":"'"$hname"'","message": "Install done - rebooting server..."}'
cp /tmp/firstboot.log ~/firstboot.log
echo "Reboot text" > /root/vpsvaletreboot.txt
reboot
