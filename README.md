# isoboot-chart

PXE boot proxy DHCP server using dnsmasq and iPXE.

## Description

This Helm chart deploys a Pod that provides PXE boot services via proxy DHCP. It does not interfere with your existing DHCP server - it only adds PXE boot information to DHCP responses.

Features:
- Proxy DHCP mode (works alongside existing DHCP server)
- Built-in TFTP server for iPXE boot files
- DNS disabled
- Regular DHCP disabled

## Prerequisites

- Kubernetes cluster with host networking support
- Existing DHCP server on the network

## Installation

```bash
helm install isoboot ./isoboot-chart --set interface=enp4s0
```

## Required Parameters

| Parameter | Description |
|-----------|-------------|
| `interface` | Network interface to bind to (e.g., `enp4s0`, `eth0`). **Required, no default.** |

## Optional Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `image.repository` | `alpine` | Container image repository |
| `image.tag` | `latest` | Container image tag |
| `image.pullPolicy` | `Always` | Image pull policy |
| `resources.limits.memory` | `128Mi` | Memory limit |
| `resources.limits.cpu` | `500m` | CPU limit |
| `resources.requests.memory` | `64Mi` | Memory request |
| `resources.requests.cpu` | `100m` | CPU request |

## How It Works

1. Pod starts with Alpine Linux
2. Installs dnsmasq and ipxe packages
3. Configures dnsmasq in proxy DHCP mode on the specified interface
4. Serves iPXE boot files via TFTP

When a PXE client boots:
1. Client gets IP from your existing DHCP server
2. dnsmasq (proxy mode) responds with PXE boot options
3. Client downloads iPXE via TFTP from this Pod
4. iPXE takes over boot process

## Uninstall

```bash
helm uninstall isoboot
```

## License

MIT
