# one-click-doh
A shell script to install a DNS over HTTPS (DoH) server with Chinese-specific configuration, EDNS support, and cache enabled, using [DNS Proxy](https://github.com/AdguardTeam/dnsproxy) and [dnsmasq-china-list](https://github.com/felixonmars/dnsmasq-china-list).

## Install

```shell
wget -q https://raw.githubusercontent.com/funnycups/one-click-doh/main/install.sh && bash install.sh
```

In theory, it supports CentOS, Fedora, Debian, and Ubuntu.

By default, the script will use Cloudflare and DNS.SB as default upstreams.

To change the default DNS upstreams configuration, please edit /home/dnsproxy/update.sh. To apply changes, either run update.sh manually or wait for it to run automatically within 3 hours.

## Uninstall

To remove the installed DoH service and configuration:

```shell
bash install.sh --uninstall
```

What this does:
- Stops and disables the `dnsproxy` systemd service, removes the unit file.
- Removes the cron job that updates `/home/dnsproxy/list.txt`.
- Deletes `/home/dnsproxy` and `/usr/bin/dnsproxy`.

DNS restore behavior:
- During install, if `nameserver 127.0.0.1` is applied, the script first backs up `/etc/resolv.conf` to `/etc/resolv.conf.bak` (if not already present).
- During uninstall, it restores `/etc/resolv.conf` from the backup when available. If no backup exists but `resolv.conf` points to `127.0.0.1`, it falls back to public DNS (Cloudflare 1.1.1.1 and Google 8.8.8.8).

For more detailed information, please visit [here](https://www.cups.moe/archives/self-build-doh.html).
