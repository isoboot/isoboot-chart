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
- `{{ .BootTarget }}` - BootTarget name (use for static file paths)
- `{{ .ProvisionName }}` - Provision name (use for answer file URLs)

## Example

```ipxe
#!ipxe
kernel http://{{ .Host }}:{{ .Port }}/static/{{ .BootTarget }}/linux
initrd http://{{ .Host }}:{{ .Port }}/static/{{ .BootTarget }}/initrd.gz
imgargs linux initrd=initrd.gz auto=true hostname={{ .Hostname }} domain={{ .Domain }} preseed/url=http://{{ .Host }}:{{ .Port }}/answer/{{ .ProvisionName }}/preseed.cfg --- quiet
boot
```

## Why .tpl Files?

Helm templates containing Go template syntax (`{{ .Var }}`) need escaping (`{{"{{" }} .Var {{"}}"  }}`). Using `.Files.Get` with separate .tpl files avoids this - the .tpl content is inserted verbatim.
