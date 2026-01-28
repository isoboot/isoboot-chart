# files/CLAUDE.md

iPXE boot templates for BootTarget resources.

## File Naming

`boottarget-{name}.tpl` - Template loaded by `templates/boottarget-{name}.yaml`

Example: `boottarget-debian-13.tpl` is loaded by `templates/boottarget-debian-13.yaml`.

## Template Variables

- `{{ .Host }}` - HTTP server IP
- `{{ .Port }}` - HTTP server port
- `{{ .MachineName }}` - Full machine name (e.g., "vm-01.lan")
- `{{ .Hostname }}` - Hostname part (first segment before dot)
- `{{ .Domain }}` - Domain part (everything after first dot)
- `{{ .BootTarget }}` - BootTarget name (use for ISO content paths)
- `{{ .ProvisionName }}` - Provision resource name (use for answer file URLs)

## Example

```ipxe
#!ipxe
kernel http://{{ .Host }}:{{ .Port }}/iso/content/{{ .BootTarget }}/mini.iso/linux
initrd http://{{ .Host }}:{{ .Port }}/iso/content/{{ .BootTarget }}/mini.iso/initrd.gz
imgargs linux initrd=initrd.gz auto=true hostname={{ .Hostname }} domain={{ .Domain }} preseed/url=http://{{ .Host }}:{{ .Port }}/answer/{{ .ProvisionName }}/preseed.cfg --- quiet
boot
```

## Why .tpl Files?

Helm templates containing Go template syntax (`{{ .Var }}`) need escaping (`{{"{{"}} .Var {{"}}"}}`). Using `.Files.Get` with separate .tpl files avoids this - the .tpl content is inserted verbatim.
