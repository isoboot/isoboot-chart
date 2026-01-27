# Milestones

## v0.1.0 - PXE Boot Infrastructure ✅

- Proxy DHCP with dnsmasq
- iPXE chainloading (BIOS + UEFI)
- Auto-detected subnet from interface

---

## v0.2.0 - Debian 13 Netboot ✅

- HTTP server serving boot files (kernel, initrd)
- On-demand ISO download with caching
- Machine CRD for MAC-to-hostname mapping
- Provision CRD for installation state (Pending/InProgress/Complete)
- iPXE conditional boot based on Provision status
- Firmware merging for non-free drivers

---

## v0.3.0 - Controller/HTTP Split ✅

- Separate controller and HTTP pods for security
- Controller has k8s API access, HTTP does not
- gRPC communication between pods
- Squid caching proxy for package downloads
- Boots to Debian 13 installer screen

---

## v0.4.0 - CRD Framework & Checksum Verification ✅

- DiskImage CRD for ISO downloads with checksum verification
- BootTarget CRD for boot configurations
- ResponseTemplate CRD for dynamic response files
- `includeFirmwarePath` for firmware merging
- Exact relative path matching for checksums
- Deployments instead of Pods (auto-restart)

---

## v0.5.0 - Preseed Automation ✅

- Renamed Deploy CRD to Provision (clearer naming)
- Simplified pod names (isoboot-controller, isoboot-http)
- Completion callback via `/boot/done` endpoint
- IP tracking in Provision status
- Console-only Debian installation with SSH
- Preseed template with ResponseTemplate CRD

---

## v0.6.0 - SSH & Security (Next)

**Objective:** SSH key management and security hardening.

### Features
- SSH authorized_keys per user via ConfigMap/Secret
- SSH host key injection (avoid known_hosts warnings)
- SSH key-only authentication (disable password login)

---

## v0.7.0 - Debian 12 (Bookworm)

**Objective:** Add Debian 12 stable support.

### Features
- Debian 12 DiskImage and BootTargets
- Preseed template for Debian 12
- Tested automated installation

### Targets
- debian-12-no-firmware
- debian-12-with-firmware

---

## v0.8.0 - Ubuntu Server

**Objective:** Ubuntu Server support with autoinstall.

### Features
- Ubuntu autoinstall (cloud-init) templates
- ResponseTemplate for autoinstall YAML generation
- Subiquity-based installation

### Targets
- ubuntu-22.04 (Jammy Jellyfish LTS)
- ubuntu-24.04 (Noble Numbat LTS)
- ubuntu-25.10 (latest)

---

## v0.9.0 - Rocky Linux

**Objective:** Rocky Linux support with kickstart.

### Features
- Kickstart template generation
- ResponseTemplate for kickstart files
- Anaconda-based installation

### Targets
- rocky-9
- rocky-10

---

## v0.10.0 - Alma Linux

**Objective:** Alma Linux support with kickstart.

### Features
- Kickstart template (shared with Rocky)
- ResponseTemplate for kickstart files

### Targets
- alma-9
- alma-10

---

## v1.0.0 - Production Ready

**Objective:** Stable release with full multi-distro support.

### Supported Distributions
| Distro | Versions | Installer |
|--------|----------|-----------|
| Debian | 12, 13 | Preseed |
| Ubuntu | 22.04, 24.04, 25.10 | Autoinstall |
| Rocky Linux | 9, 10 | Kickstart |
| Alma Linux | 9, 10 | Kickstart |

### Features
- Boot menu for multiple OS options
- Default timeout with auto-boot
- Machine-specific menu customization
- Comprehensive documentation
- Production hardening

---

## Future Ideas (Post 1.0)

- Web UI for managing machines and provisions
- PXE boot logging and metrics
- Integration with external IPAM
- Cloud-init support for cloud images
- Windows Server support (WinPE/MDT)
- ESXi support
