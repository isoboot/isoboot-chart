#!ipxe
kernel http://{{ .Host }}:{{ .Port }}/static/{{ .BootTarget }}/linux
initrd http://{{ .Host }}:{{ .Port }}/static/{{ .BootTarget }}/firmware-initrd.gz
imgargs linux initrd=firmware-initrd.gz auto=true priority=critical ipv6.disable=1 netcfg/choose_interface=auto hostname={{ .Hostname }} domain={{ .Domain }} mirror/http/proxy=http://{{ .Host }}:{{ .ProxyPort }} preseed/url=http://{{ .Host }}:{{ .Port }}/dynamic/answer/{{ .ProvisionName }}/preseed.cfg --- quiet
boot
