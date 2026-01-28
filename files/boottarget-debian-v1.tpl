#!ipxe
kernel http://{{ .Host }}:{{ .Port }}/iso/content/{{ .BootTarget }}/mini.iso/linux
initrd http://{{ .Host }}:{{ .Port }}/iso/content/{{ .BootTarget }}/mini.iso/initrd.gz
imgargs linux initrd=initrd.gz auto=true priority=critical ipv6.disable=1 netcfg/choose_interface=auto hostname={{ .Hostname }} domain={{ .Domain }} mirror/http/proxy=http://{{ .Host }}:3128 preseed/url=http://{{ .Host }}:{{ .Port }}/answer/{{ .ProvisionName }}/preseed.cfg --- quiet
boot
