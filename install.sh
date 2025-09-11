#!/bin/bash
center_print(){
	text=$1
	terminal_width=$(tput cols)
	text_length=${#text}
	leading_spaces=$(( (terminal_width - text_length) / 2 ))
	padding=$(printf '%*s' "$leading_spaces")
	echo "${padding}${text}"
}

# Uninstall function and arg handling
uninstall_doh(){
	if [[ $EUID -ne 0 ]]; then
		echo "Please run as root (use sudo)."
		exit 1
	fi
	echo "Uninstalling DoH service and configuration..."

	# Stop and disable systemd service if available
	if command -v systemctl >/dev/null 2>&1; then
		if systemctl list-unit-files | grep -q '^dnsproxy\.service'; then
			systemctl stop dnsproxy 2>/dev/null || true
			systemctl disable dnsproxy 2>/dev/null || true
		fi
		# Remove service file and reload daemon
		if [[ -f /etc/systemd/system/dnsproxy.service ]]; then
			rm -f /etc/systemd/system/dnsproxy.service
			systemctl daemon-reload || true
		fi
	fi

	# Remove cron job that runs update.sh every 3 hours
	if crontab -l >/tmp/.one_click_doh_cron 2>/dev/null; then
		grep -v '/home/dnsproxy/update.sh' /tmp/.one_click_doh_cron | crontab -
		rm -f /tmp/.one_click_doh_cron
	fi

	# Remove installed files and binary
	rm -rf /home/dnsproxy
	if [[ -f /usr/bin/dnsproxy ]]; then
		rm -f /usr/bin/dnsproxy
	fi

	# Restore DNS resolver configuration if possible
	if [[ -f /etc/resolv.conf.bak ]]; then
		if cp -a /etc/resolv.conf.bak /etc/resolv.conf 2>/dev/null || cp /etc/resolv.conf.bak /etc/resolv.conf; then
			rm -f /etc/resolv.conf.bak
		else
			echo "Warning: failed to restore /etc/resolv.conf from backup; backup kept at /etc/resolv.conf.bak."
		fi
	else
		# If resolv.conf points to 127.0.0.1, fallback to public DNS (Cloudflare/Google)
		if grep -qE '^\s*nameserver\s+127\.0\.0\.1(\s|$)' /etc/resolv.conf 2>/dev/null; then
			{
				echo 'nameserver 1.1.1.1'
				echo 'nameserver 8.8.8.8'
			} > /etc/resolv.conf
		fi
	fi

	echo "DoH uninstalled. resolv.conf has been restored from backup when available, otherwise switched from 127.0.0.1 to public DNS (1.1.1.1/8.8.8.8) if needed."
	exit 0
}

# Handle --uninstall early before proceeding with installation
if [[ "$1" == "--uninstall" || "$1" == "-u" ]]; then
	uninstall_doh
fi
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
center_print 'https://www.cups.moe/archives/self-build-doh.html'
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
mv -f dnsproxy /usr/bin/dnsproxy
cd /tmp/install
rm -rf linux-amd64 dnsproxy.tar.gz

#set up crontab and make list.txt
mkdir -p /home/dnsproxy
echo -e '#!/bin/bash
echo "https://1.1.1.1/dns-query
https://hk-hkg.doh.sb/dns-query
https://jp-nrt.doh.sb/dns-query" > /home/dnsproxy/list.txt'"
curl -s https://raw.githubusercontent.com/felixonmars/dnsmasq-china-list/master/accelerated-domains.china.conf| awk -F'[=/]' '{print \"[/\" \$3 \"/]https://doh.pub/dns-query\"}' >> /home/dnsproxy/list.txt
systemctl restart dnsproxy" > /home/dnsproxy/update.sh
(echo "0 */3 * * * bash /home/dnsproxy/update.sh" && crontab -l)|crontab
#generate first
echo "https://1.1.1.1/dns-query
https://hk-hkg.doh.sb/dns-query
https://jp-nrt.doh.sb/dns-query" > /home/dnsproxy/list.txt
curl -s https://raw.githubusercontent.com/felixonmars/dnsmasq-china-list/master/accelerated-domains.china.conf| awk -F'[=/]' '{print "[/" $3 "/]https://doh.pub/dns-query"}' >> /home/dnsproxy/list.txt

#get the ssl certificate
if [[ ! -d ~/.acme.sh ]];then
	curl https://get.acme.sh | sh -s email=my@example.com
fi
source ~/.bashrc
if [[ $webdir ]];then
	~/.acme.sh/acme.sh --issue -d $domain --webroot $webdir
else
	$pkg_manager install -y socat
	~/.acme.sh/acme.sh --issue -d $domain --standalone
fi

#set up systemd
echo "[Unit]
Description=DNS Proxy
After=network.target
Requires=network.target

[Service]
Type=simple
ExecStart=/usr/bin/dnsproxy -l 127.0.0.1 -p $port -u /home/dnsproxy/list.txt -b 1.1.1.1 --https-port=$https_port --tls-crt=/home/dnsproxy/ssl.crt --tls-key=/home/dnsproxy/ssl.key --upstream-mode parallel --cache --edns
Restart=on-failure

[Install]
WantedBy=multi-user.target" > /etc/systemd/system/dnsproxy.service
if [[ $port = 53 ]];then
	# Backup resolv.conf
	if [[ ! -f /etc/resolv.conf.bak ]]; then
		if cp -a /etc/resolv.conf /etc/resolv.conf.bak 2>/dev/null || cp /etc/resolv.conf /etc/resolv.conf.bak; then
			:
		else
			echo "Warning: failed to backup /etc/resolv.conf to /etc/resolv.conf.bak; continuing."
		fi
	fi
	echo "nameserver 127.0.0.1" > /etc/resolv.conf
fi
systemctl daemon-reload
systemctl enable dnsproxy

#generate the ssl file
~/.acme.sh/acme.sh --install-cert -d $domain \
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
center_print 'https://www.cups.moe/archives/self-build-doh.html'
exit 0
