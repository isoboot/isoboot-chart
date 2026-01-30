# crds/CLAUDE.md

Custom Resource Definitions for isoboot.

## Resources

### Machine
Represents a physical/virtual machine identified by MAC address.
```yaml
apiVersion: isoboot.io/v1alpha1
kind: Machine
metadata:
  name: vm-01.lan
spec:
  mac: "aa-bb-cc-dd-ee-ff"
  machineId: "0123456789abcdef0123456789abcdef"  # optional, 32 hex chars
```
- `mac` (required): MAC address, dash-separated
- `machineId` (optional): systemd machine-id for /etc/machine-id (exactly 32 lowercase hex characters)

### BootTarget
Downloads files and defines how to boot a specific OS/configuration.
```yaml
apiVersion: isoboot.io/v1alpha1
kind: BootTarget
metadata:
  name: debian-13
spec:
  files:
    - url: "https://deb.debian.org/.../linux"
      checksumURL: "https://deb.debian.org/.../SHA256SUMS"
    - url: "https://deb.debian.org/.../initrd.gz"
      checksumURL: "https://deb.debian.org/.../SHA256SUMS"
    - url: "https://cdimage.debian.org/.../firmware.cpio.gz"
      checksumURL: "https://cdimage.debian.org/.../SHA256SUMS"
  combinedFiles:
    - name: firmware-initrd.gz
      sources:
        - initrd.gz
        - firmware.cpio.gz
  template: |
    #!ipxe
    ...
```
- `files` (required): Files to download directly from upstream URLs
- `combinedFiles` (optional): Files built by concatenating downloaded files
- `template` (required): iPXE boot template

Status phases: Pending → Downloading → Complete/Failed

### Provision
Triggers installation of a Machine using a BootTarget.
```yaml
apiVersion: isoboot.io/v1alpha1
kind: Provision
metadata:
  name: vm-01-debian-13
spec:
  machineRef: vm-01.lan
  bootTargetRef: debian-13
  responseTemplateRef: debian-standard
  configMaps:
    - config-01
  secrets:
    - secret-01
```
Status phases: Pending → InProgress → Complete/Failed/ConfigError

### ResponseTemplate
Templates for answer files (preseed, kickstart, etc.).
```yaml
apiVersion: isoboot.io/v1alpha1
kind: ResponseTemplate
metadata:
  name: debian-standard
spec:
  files:
    preseed.cfg: |
      d-i netcfg/get_hostname string {{ .Hostname }}
      ...
```

## Naming Conventions

- Machine: FQDN format (`vm-01.lan`)
- BootTarget: OS version (`debian-12`, `debian-13`)
- Provision: Machine + BootTarget (`vm-01-debian-13`)
