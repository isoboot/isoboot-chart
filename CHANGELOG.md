# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
