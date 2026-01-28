# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.5.0] - 2026-01-27

### Breaking Changes
- **Resource naming changed**: `isoboot.fullname` no longer includes the chart name. If upgrading from a previous version:
  - Set `fullnameOverride: <release-name>-isoboot` in values.yaml to preserve old resource names, OR
  - Uninstall and reinstall the chart (existing resources will be orphaned)

### Added
- IP tracking in Provision status - captures source IP when `/boot/done` is called
- IP column in `kubectl get provision` output
- Completion callback endpoint (`/boot/done?id={hostname}`)
- Console-only Debian installation with SSH server

### Changed
- Renamed Deploy CRD to Provision (avoid confusion with Kubernetes Deployment)
- Simplified pod names: `isoboot-controller` instead of `isoboot-isoboot-chart-controller`
- Updated RBAC rules for `provisions` resource

### Technical Details
- Provision status now includes `ip` field populated on completion
- Proto updated with `ip` field in `MarkBootCompletedRequest`
- Uses `net.SplitHostPort()` for IPv6-compatible IP extraction

### Tested With
- Debian 13 (trixie) automated installation via preseed
- QEMU VM with UEFI PXE boot on Raspberry Pi 5 cluster
- IP tracking verified in kubectl output

## [0.4.0] - 2026-01-26

### Added
- DiskImage CRD for managing ISO downloads with checksum verification
- BootTarget CRD for defining boot configurations per disk image
- ResponseTemplate CRD for dynamic response file generation
- `includeFirmwarePath` field in BootTarget for firmware merging
- Separate BootTargets for debian-13 (with and without firmware)
- ISO storage volume mounted to controller for DiskImage downloads
- Squid proxy cache for boot file downloads

### Changed
- Renamed `target` to `bootTargetRef` in Deploy CRD
- Converted controller and HTTP from Pods to Deployments (auto-restart)
- Reduced squid shutdown wait time to 5 seconds

### Fixed
- Checksum verification now uses exact relative path matching
- Basename fallback for checksum files with only base filenames
- SHA256SUMS with multiple same-named files (e.g., netboot/mini.iso vs netboot/gtk/mini.iso)

### Tested With
- Debian 13 (trixie) netboot with SHA256 verification
- Firmware merging with firmware.cpio.gz

## [0.3.0] - 2026-01-24

### Added
- Separate controller pod with gRPC server (k8s API access isolated)
- Controller Service for internal gRPC communication
- Squid caching proxy pod for package downloads

### Changed
- Split HTTP and controller into separate pods for security
- HTTP pod no longer has Kubernetes API access
- HTTP pod uses `dnsPolicy: ClusterFirstWithHostNet` to resolve cluster DNS
- Controller memory increased to 2Gi for Go compilation
- Updated to golang:1.25-alpine image

### Fixed
- Startup order issue: HTTP pod uses lazy gRPC connection
- DNS resolution for hostNetwork pods

### Tested With
- Debian 13 (trixie) netboot - boots to installer screen
- QEMU VM with UEFI PXE boot

## [0.2.0] - 2026-01-24

### Added
- HTTP pod running isoboot-http server for Debian netboot
- Machine CRD for MAC-to-hostname mapping
- Deploy CRD for managing installation state (Pending/InProgress/Completed)
- iPXE boot templates with conditional boot based on Deploy status
- ConfigMaps for server config and boot templates
- RBAC (ServiceAccount, Role, RoleBinding) for CRD access
- Firmware merging support for non-free drivers

### Changed
- Chart version bumped to 0.2.0
- Description updated to "PXE boot proxy DHCP server with Debian netboot support"
- MAC addresses now use dash-separated format (iPXE compatible)

### Technical Details
- HTTP pod uses golang:1.23-alpine and installs isoboot-http at startup
- ISO files cached in /opt/isoboot/iso (hostPath volume)
- Boot templates served from ConfigMap
- Supports hot-reload of config.yaml

### Tested With
- Debian 13 (trixie) netboot mini.iso
- QEMU VM with UEFI PXE boot
- Conditional boot with Machine/Deploy CRDs

## [0.1.0] - 2026-01-23

### Added
- Initial Helm chart for PXE boot proxy DHCP server
- Pod deployment with dnsmasq and iPXE
- Proxy DHCP mode - works alongside existing DHCP server
- Built-in TFTP server serving iPXE boot files
- Auto-detection of subnet from specified interface
- Support for both BIOS (undionly.kpxe) and UEFI (ipxe.efi) PXE clients
- Liveness and readiness probes using `pidof dnsmasq`
- Required parameter validation with clear error message
- CLAUDE.md for project context

### Technical Details
- Uses `hostNetwork: true` for direct access to network interface
- Downloads iPXE binaries from boot.ipxe.org at startup
- Generates dnsmasq config at runtime for subnet auto-detection
- Requires `NET_ADMIN` and `NET_RAW` capabilities
- Ports used: 67 (DHCP), 69 (TFTP), 4011 (ProxyDHCP)

### Tested With
- microk8s on Ubuntu
- QEMU VM with UEFI PXE boot
- Bridge interface on 192.168.88.0/24 network
