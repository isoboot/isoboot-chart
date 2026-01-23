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

- Kubernetes cluster with Multus CNI
- Existing DHCP server on the network

### Install Multus CNI

```bash
kubectl apply -f https://raw.githubusercontent.com/k8snetworkplumbingwg/multus-cni/master/deployments/multus-daemonset.yml
```

The chart automatically deploys the CNI DHCP daemon via DaemonSet.

## Installation

```bash
helm install isoboot ./isoboot-chart --set interface=enp4s0
```

## Required Parameters

| Parameter | Description |
|-----------|-------------|
| `interface` | Host interface for macvlan (e.g., `br1`, `eth0`). Pod gets its own IP via DHCP. **Required, no default.** |

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

1. Chart creates a macvlan NetworkAttachmentDefinition on the specified interface
2. Pod gets its own IP via DHCP on the network
3. Pod installs dnsmasq and downloads iPXE binaries
4. dnsmasq runs in proxy DHCP mode on the macvlan interface
5. Serves iPXE boot files via TFTP

When a PXE client boots:
1. Client gets IP from your existing DHCP server
2. dnsmasq (proxy mode) responds with PXE boot options
3. Client downloads iPXE via TFTP from the Pod's macvlan IP
4. iPXE takes over boot process

## Uninstall

```bash
helm uninstall isoboot
```

## License

MIT
