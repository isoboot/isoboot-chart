# Milestones

## v0.1.0 - PXE Boot Infrastructure (Complete)

- Proxy DHCP with dnsmasq
- iPXE chainloading (BIOS + UEFI)
- Auto-detected subnet from interface

---

## v0.2.0 - Debian 13 Netboot (Complete)

- HTTP server serving boot files (kernel, initrd)
- On-demand ISO download with caching
- Machine CRD for MAC-to-hostname mapping
- Deploy CRD for installation state (Pending/InProgress/Complete)
- iPXE conditional boot based on Deploy status
- Firmware merging for non-free drivers

---

## v0.3.0 - Controller/HTTP Split (Complete)

- Separate controller and HTTP pods for security
- Controller has k8s API access, HTTP does not
- gRPC communication between pods
- Squid caching proxy for package downloads
- Boots to Debian 13 installer screen

---

## v0.4.0 - Preseed Automation (Next)

**Objective:** Fully automated Debian installation with preseed.

### Features
- Preseed template with variables (hostname, domain, root password, etc.)
- Per-machine preseed configuration via Deploy CRD
- Late command support for post-install customization
- Completion callback to mark Deploy as Complete
- Partitioning presets (single disk, LVM, etc.)

### Deploy CRD Extension
```yaml
apiVersion: isoboot.io/v1alpha1
kind: Deploy
metadata:
  name: vm03-debian-13
spec:
  machineRef: vm03
  bootTargetRef: debian-13
  preseed:
    hostname: vm03
    domain: local
    timezone: America/Los_Angeles
    locale: en_US.UTF-8
    rootPassword: "$6$..." # hashed
    partitioning: lvm-single-disk
    packages:
      - openssh-server
      - vim
    lateCommand: |
      curl -X POST http://{{.Host}}:{{.Port}}/api/deploy/{{.Hostname}}/complete
```

---

## v0.5.0 - Multi-OS Support (Future)

- Ubuntu Server support
- Rocky Linux / AlmaLinux support
- OS-specific templates (preseed, autoinstall, kickstart)

---

## v0.6.0 - Boot Menu (Future)

- Interactive boot menu for multiple OS options
- Default timeout with auto-boot
- Machine-specific menu customization

---

## Future Ideas

- Web UI for managing machines and deploys
- PXE boot logging and metrics
- Integration with external IPAM
- Cloud-init support for cloud images
