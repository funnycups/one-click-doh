# one-click-doh
A shell script to install a DNS over HTTPS (DoH) server with Chinese-specific configuration, EDNS support, and cache enabled, using [DNS Proxy](https://github.com/AdguardTeam/dnsproxy) and [dnsmasq-china-list](https://github.com/felixonmars/dnsmasq-china-list).

```shell
wget -q https://raw.githubusercontent.com/funnycups/one-click-doh/main/install.sh && bash install.sh
```

In theory, it supports CentOS, Fedora, Debian, and Ubuntu.

By default, the script will use Cloudflare and DNS.SB as default upstreams.

To change the default DNS upstreams configuration, please edit /home/dnsproxy/update.sh. To apply changes, either run update.sh manually or wait for it to run automatically within 3 hours.

For more detailed information, please visit [here](https://www.xh-ws.com/archives/self-build-doh.html).
