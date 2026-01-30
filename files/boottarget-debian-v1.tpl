#!ipxe
kernel http://{{ .Host }}:{{ .Port }}/static/{{ .BootMedia }}/{{ .KernelFilename }}
{{- if .HasFirmware }}
{{- if .UseDebianFirmware }}
initrd http://{{ .Host }}:{{ .Port }}/static/{{ .BootMedia }}/with-firmware/{{ .InitrdFilename }}
{{- else }}
initrd http://{{ .Host }}:{{ .Port }}/static/{{ .BootMedia }}/no-firmware/{{ .InitrdFilename }}
{{- end }}
{{- else }}
initrd http://{{ .Host }}:{{ .Port }}/static/{{ .BootMedia }}/{{ .InitrdFilename }}
{{- end }}
imgargs {{ .KernelFilename }} initrd={{ .InitrdFilename }} auto=true priority=critical ipv6.disable=1 netcfg/choose_interface=auto hostname={{ .Hostname }} domain={{ .Domain }} mirror/http/proxy=http://{{ .Host }}:{{ .ProxyPort }} preseed/url=http://{{ .Host }}:{{ .Port }}/dynamic/answer/{{ .ProvisionName }}/preseed.cfg --- quiet
boot
