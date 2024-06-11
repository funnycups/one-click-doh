#!/bin/bash
center_print(){
	text=$1
	terminal_width=$(tput cols)
	text_length=${#text}
	leading_spaces=$(( (terminal_width - text_length) / 2 ))
	padding=$(printf '%*s' "$leading_spaces")
	echo "${padding}${text}"
}
#install crontab,wget and curl,net-tools
echo "Installing essential software, please wait..."
if [[ -x `command -v yum` ]];then
	pkg_manager='yum'
	cron='cronie'
elif [[ -x `command -v apt-get` ]];then
	pkg_manager='apt-get'
	cron='cron'
else
	echo 'System not supported currently. Neither yum nor apt-get was found.'
	exit -1
fi
$pkg_manager install -y curl wget $cron net-tools
clear
center_print '============================================================='
center_print 'DoH server one-click installation'
center_print 'Install DoH server with Chinese-specific configuration'
center_print 'More detailed information at'
center_print 'https://www.xh-ws.com/archives/self-build-doh.html'
center_print '============================================================='
echo -n "Would you like to make this server itself use the installed DoH service?(y/n):"
read self
if [[ $self = 'y' || $self = 'Y' || $self = 'yes' ]];then
	port=53
elif [[ $self = 'n' || $self = 'N' || $self = 'no' ]];then
	port=0
else
	echo 'Unknown input!'
	exit -1
fi
read -p "Please enter a domain which has already been pointed to this server:" domain
webdir=
if netstat -tuln | grep -q ":80"; then
    read -p "Warning: Port 80 is in use. If you are running a web server, specifying the web root directory of $domain is needed:" webdir
fi
read -p "Please enter a port for the DoH server to listen on.
You may use a port other than 443 and use a reverse proxy to redirect HTTPS requests to the specified port:" https_port

read -p "Press Enter to continue or Ctrl+C to interrupt" e


mkdir -p /tmp/install
cd /tmp/install

#install dnsproxy
VERSION=$(curl -s https://api.github.com/repos/AdguardTeam/dnsproxy/releases/latest | grep tag_name | cut -d '"' -f 4)
wget -O dnsproxy.tar.gz "https://github.com/AdguardTeam/dnsproxy/releases/download/${VERSION}/dnsproxy-linux-amd64-${VERSION}.tar.gz"
tar -xzvf dnsproxy.tar.gz
cd linux-amd64
mv dnsproxy /usr/bin/dnsproxy
cd /tmp/install

#set up crontab and make list.txt
mkdir -p /home/dnsproxy
echo -e '#!/bin/bash
echo "https://dns11.quad9.net:443/dns-query
https://1.1.1.1/dns-query
https://unfiltered.adguard-dns.com/dns-query
https://hk-hkg.doh.sb/dns-query
https://jp-nrt.doh.sb/dns-query
https://freedns.controld.com/p0
https://8.8.8.8/dns-query" > /home/dnsproxy/list.txt'"
curl -s https://raw.githubusercontent.com/felixonmars/dnsmasq-china-list/master/accelerated-domains.china.conf| awk -F'[=/]' '{print \"[/\" \$3 \"/]https://doh.pub/dns-query\"}' >> /home/dnsproxy/list.txt
systemctl restart dnsproxy" > /home/dnsproxy/update.sh
(echo "0 */3 * * * bash /home/dnsproxy/update.sh" && crontab -l)|crontab
#generate first
echo "https://dns11.quad9.net:443/dns-query
https://1.1.1.1/dns-query
https://unfiltered.adguard-dns.com/dns-query
https://hk-hkg.doh.sb/dns-query
https://jp-nrt.doh.sb/dns-query
https://freedns.controld.com/p0
https://8.8.8.8/dns-query" > /home/dnsproxy/list.txt
curl -s https://raw.githubusercontent.com/felixonmars/dnsmasq-china-list/master/accelerated-domains.china.conf| awk -F'[=/]' '{print "[/" $3 "/]https://doh.pub/dns-query"}' >> /home/dnsproxy/list.txt

#get the ssl certificate
if [[ ! -d ~/.acme.sh ]];then
	curl https://get.acme.sh | sh -s email=my@example.com
	source ~/.bashrc
fi
if [[ $webdir ]];then
	acme.sh --issue -d $domain --webroot $webdir
else
	$pkg_manager install -y socat
	acme.sh --issue -d $domain --standalone
fi

#set up systemd
echo "[Unit]
Description=DNS Proxy
After=network.target
Requires=network.target

[Service]
Type=simple
ExecStart=/usr/bin/dnsproxy -l 127.0.0.1 -p $port -u /home/dnsproxy/list.txt -b https://1.1.1.1/dns-query --https-port=$https_port --tls-crt=/home/dnsproxy/ssl.crt --tls-key=/home/dnsproxy/ssl.key --all-servers --cache --edns
Restart=on-failure

[Install]
WantedBy=multi-user.target" > /etc/systemd/system/dnsproxy.service
if [[ $port = 53 ]];then
	echo "nameserver 127.0.0.1" > /etc/resolv.conf
fi
systemctl daemon-reload
systemctl enable dnsproxy

#generate the ssl file
acme.sh --install-cert -d $domain \
--key-file       /home/dnsproxy/ssl.key  \
--fullchain-file /home/dnsproxy/ssl.crt \
--reloadcmd     "systemctl restart dnsproxy"

ui_port=
if [[ $https_port != 443 ]];then
	ui_port=":$https_port"
fi
clear
center_print '============================================================='
center_print 'All done!'
center_print "You can now use DoH through https://${domain}${ui_port}/dns-query"
center_print 'More information at'
center_print 'https://www.xh-ws.com/archives/self-build-doh.html'
exit 0
