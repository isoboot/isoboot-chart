# files/CLAUDE.md

iPXE boot templates for BootTarget resources.

## File Naming

`boottarget-{name}.tpl` - Template loaded by `templates/boottarget-{name}.yaml`

Example: `boottarget-debian-v1.tpl` is loaded by all `templates/boottarget-debian-*.yaml` files.

## Template Variables

- `{{ .Host }}` - HTTP server IP
- `{{ .Port }}` - HTTP server port
- `{{ .ProxyPort }}` - Squid proxy port
- `{{ .MachineName }}` - Full machine name (use for answer file URLs)
- `{{ .Hostname }}` - Hostname part (first segment before dot)
- `{{ .Domain }}` - Domain part (everything after first dot)
- `{{ .BootTarget }}` - BootTarget name
- `{{ .BootSource }}` - BootSource name (use for static file paths)
- `{{ .UseFirmware }}` - bool, whether to use firmware-combined initrd
- `{{ .ProvisionName }}` - Provision name (use for answer file URLs)
- `{{ .KernelFilename }}` - kernel filename (e.g., "linux")
- `{{ .InitrdFilename }}` - initrd filename (e.g., "initrd.gz")
- `{{ .HasFirmware }}` - bool, whether BootSource has firmware defined

## Example

```ipxe
#!ipxe
kernel http://{{ .Host }}:{{ .Port }}/static/{{ .BootSource }}/{{ .KernelFilename }}
{{- if and .HasFirmware .UseFirmware }}
initrd http://{{ .Host }}:{{ .Port }}/static/{{ .BootSource }}/with-firmware/{{ .InitrdFilename }}
{{- else if .HasFirmware }}
initrd http://{{ .Host }}:{{ .Port }}/static/{{ .BootSource }}/no-firmware/{{ .InitrdFilename }}
{{- else }}
initrd http://{{ .Host }}:{{ .Port }}/static/{{ .BootSource }}/{{ .InitrdFilename }}
{{- end }}
imgargs {{ .KernelFilename }} initrd={{ .InitrdFilename }} auto=true hostname={{ .Hostname }} domain={{ .Domain }} preseed/url=http://{{ .Host }}:{{ .Port }}/dynamic/answer/{{ .ProvisionName }}/preseed.cfg --- quiet
boot
```

## Why .tpl Files?

Helm templates containing Go template syntax (`{{ .Var }}`) need escaping (`{{ "{{" }} .Var {{ "}}" }}`). Using `.Files.Get` with separate .tpl files avoids this - the .tpl content is inserted verbatim.
