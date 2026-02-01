# isoboot-chart

PXE boot proxy DHCP server using dnsmasq and iPXE.

## Description

This Helm chart deploys a Pod that provides PXE boot services via proxy DHCP. It does not interfere with your existing DHCP server - it only adds PXE boot information to DHCP responses.

Features:
- Proxy DHCP mode (works alongside existing DHCP server)
- Built-in TFTP server serving iPXE boot files
- Auto-detects subnet from the specified interface
- Supports both BIOS (undionly.kpxe) and UEFI (ipxe.efi) PXE clients

## Motivation
- I like tinkerbell.org but, I didn't want to use a cloud image.
- I like MAAS but, my machine did not have BMC.

## Prerequisites

- Kubernetes cluster
- Existing DHCP server on the network
- No other TFTP server running on port 69

## Installation

```bash
helm install isoboot ./isoboot-chart --set interface=br1
```

## Required Parameters

| Parameter | Description |
|-----------|-------------|
| `interface` | Network interface to bind to (e.g., `br1`, `eth0`). Subnet is auto-detected. **Required.** |

## Optional Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `image.repository` | `alpine` | Container image repository |
| `image.tag` | `3.23` | Container image tag |
| `image.pullPolicy` | `IfNotPresent` | Image pull policy |
| `resources.limits.memory` | `128Mi` | Memory limit |
| `resources.limits.cpu` | `500m` | CPU limit |
| `resources.requests.memory` | `64Mi` | Memory request |
| `resources.requests.cpu` | `100m` | CPU request |

## How It Works

1. Pod runs with `hostNetwork: true` to access the specified interface
2. Auto-detects the subnet from the interface IP (e.g., `192.168.88.216/24` → `192.168.88.0`)
3. Installs dnsmasq and downloads iPXE binaries at startup
4. Runs dnsmasq in proxy DHCP mode on the detected subnet
5. Serves iPXE boot files via built-in TFTP server

When a PXE client boots:
1. Client broadcasts DHCP Discover
2. Your existing DHCP server offers an IP address
3. dnsmasq (proxy mode) responds with PXE boot options (next-server, boot filename)
4. Client downloads iPXE via TFTP
5. iPXE loads and can chain to further boot scripts

## Ports Used

| Port | Protocol | Purpose |
|------|----------|---------|
| 67 | UDP | DHCP (proxy mode, dnsmasq) |
| 69 | UDP | TFTP (dnsmasq) |
| 80 | TCP | HTTP server (isoboot-http, internal) |
| 3128 | TCP | Caching proxy (squid) |
| 4011 | UDP | PXE proxy DHCP (dnsmasq) |
| 8080 | TCP | Reverse proxy (nginx, external) |
| 18080 | TCP | gRPC (isoboot-controller) |

## Uninstall

```bash
helm uninstall isoboot
```

## License

MIT
