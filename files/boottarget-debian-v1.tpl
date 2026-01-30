#!ipxe
kernel http://{{ .Host }}:{{ .Port }}/static/{{ .BootTarget }}/linux
initrd http://{{ .Host }}:{{ .Port }}/static/{{ .BootTarget }}/initrd.gz
imgargs linux initrd=initrd.gz auto=true priority=critical ipv6.disable=1 netcfg/choose_interface=auto hostname={{ .Hostname }} domain={{ .Domain }} mirror/http/proxy=http://{{ .Host }}:{{ .ProxyPort }} preseed/url=http://{{ .Host }}:{{ .Port }}/answer/{{ .ProvisionName }}/preseed.cfg --- quiet
boot
