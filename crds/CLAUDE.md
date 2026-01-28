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
```
- `mac` (required): MAC address, dash-separated

### DiskImage
Downloads and caches ISO images with checksum verification.
```yaml
apiVersion: isoboot.io/v1alpha1
kind: DiskImage
metadata:
  name: debian-13
spec:
  iso: "https://..."
  firmware: "https://..."  # optional
```
Status phases: Pending → Verifying → Downloading → Complete/Failed

### BootTarget
Defines how to boot a specific OS/configuration.
```yaml
apiVersion: isoboot.io/v1alpha1
kind: BootTarget
metadata:
  name: debian-13-no-firmware
spec:
  diskImageRef: debian-13
  includeFirmwarePath: ""  # or "/initrd.gz" to merge firmware
  template: |
    #!ipxe
    ...
```

### Provision
Triggers installation of a Machine using a BootTarget.
```yaml
apiVersion: isoboot.io/v1alpha1
kind: Provision
metadata:
  name: vm-01-debian-13
spec:
  machineRef: vm-01.lan
  bootTargetRef: debian-13-no-firmware
  responseTemplateRef: debian-standard
  machineId: "0123456789abcdef0123456789abcdef"  # optional, 32 hex chars
  configMaps:
    - config-01
  secrets:
    - secret-01
```
- `machineId` (optional): systemd machine-id for /etc/machine-id (exactly 32 lowercase hex characters)

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
- DiskImage: OS identifier (`debian-13`)
- BootTarget: OS + variant (`debian-13-no-firmware`, `debian-13-with-firmware`)
- Provision: Machine + BootTarget (`vm-01-debian-13-no-firmware`)
