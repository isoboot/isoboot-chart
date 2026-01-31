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

### BootMedia
Downloads and caches boot files (kernel, initrd, firmware).
```yaml
apiVersion: isoboot.io/v1alpha1
kind: BootMedia
metadata:
  name: debian-12
spec:
  kernel:
    url: "https://deb.debian.org/.../linux"
    checksumURL: "https://deb.debian.org/.../SHA256SUMS"
  initrd:
    url: "https://deb.debian.org/.../initrd.gz"
    checksumURL: "https://deb.debian.org/.../SHA256SUMS"
  firmware:
    url: "https://cdimage.debian.org/.../firmware.cpio.gz"
    checksumURL: "https://cdimage.debian.org/.../SHA256SUMS"
```
- Either (`kernel` + `initrd`) or `iso` (with `iso.kernel`/`iso.initrd` extraction paths) — not both
- `firmware` is always optional
- Status phases: Pending → Downloading → Complete/Failed

Directory layout without firmware (flat):
```
debian-12/
  linux       ← kernel
  initrd.gz   ← initrd
```

Directory layout with firmware (subdirectories):
```
debian-12/
  linux                   ← kernel (always top-level)
  no-firmware/
    initrd.gz             ← original initrd
  with-firmware/
    initrd.gz             ← initrd + firmware.cpio.gz concatenated
```

### BootTarget
Defines how to boot a specific OS/configuration, referencing a BootMedia.
```yaml
apiVersion: isoboot.io/v1alpha1
kind: BootTarget
metadata:
  name: debian-12
spec:
  bootMediaRef: debian-12
  useFirmware: true
  template: |
    #!ipxe
    ...
```
- `bootMediaRef` (required): Reference to BootMedia resource
- `useFirmware` (optional): Whether to use with-firmware/ initrd
- `template` (required): iPXE boot template

### Provision
Triggers installation of a Machine using a BootTarget.
```yaml
apiVersion: isoboot.io/v1alpha1
kind: Provision
metadata:
  name: vm-01-debian-12
spec:
  machineRef: vm-01.lan
  bootTargetRef: debian-12
  responseTemplateRef: debian-standard
  configMaps:
    - config-01
  secrets:
    - secret-01
```
Status phases: Pending → WaitingForBootMedia → InProgress → Complete/Failed/ConfigError

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
- BootMedia: OS version (`debian-12`, `debian-13`)
- BootTarget: OS version or variant (`debian-12`, `debian-12-no-firmware`)
- Provision: Machine + BootTarget (`vm-01-debian-12`)
