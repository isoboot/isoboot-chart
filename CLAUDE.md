# CLAUDE.md

Helm chart for isoboot - PXE boot infrastructure on Kubernetes.

## Project Context

This repo works alongside `isoboot` (Go code for controller and HTTP server). Together they provide:
- **dnsmasq**: Proxy DHCP for PXE boot (this chart)
- **isoboot-controller**: Watches Deploy CRs, manages boot workflows (Go repo)
- **isoboot-http**: Serves iPXE scripts, ISO content, answer files (Go repo)

## Git Conventions

- **Never force push** - use squash merge at PR merge time
- PRs required for main branch

## Chart Overview

Deploys a PXE boot proxy DHCP server using dnsmasq and iPXE. Enables network booting without replacing your existing DHCP server.

## Architecture

- **Pod with hostNetwork**: Uses the host's network stack to bind to DHCP/TFTP ports
- **dnsmasq**: Runs in proxy DHCP mode - responds to PXE requests without handing out IP addresses
- **iPXE**: Boot files (undionly.kpxe for BIOS, ipxe.efi for UEFI) served via TFTP

## Key Design Decisions

1. **hostNetwork over macvlan/multus**: We tried macvlan with Multus CNI but the CNI DHCP daemon couldn't properly access network namespaces from within a container. hostNetwork is simpler and works reliably.

2. **Runtime config generation**: The dnsmasq config is generated at pod startup (not via ConfigMap) to allow auto-detection of the subnet from the interface.

3. **Auto-detected subnet**: The pod extracts the network address from the interface IP using `ip` and `awk`, eliminating a required parameter.

4. **Alpine + runtime install**: Uses Alpine base image and installs dnsmasq/iproute2 at startup. This trades startup time for simpler maintenance (no custom image to build).

## File Structure

```
crds/                 # Custom Resource Definitions
├── machine.yaml
├── deploy.yaml
├── boottarget.yaml
├── diskimage.yaml
└── responsetemplate.yaml
templates/            # Kubernetes resources
├── _helpers.tpl
├── pod.yaml
├── boottarget-*.yaml
└── ...
files/                # Template files loaded via .Files.Get
└── boottarget-debian-13.tpl
values.yaml
Chart.yaml
```

## CRD Guidelines

### Escaping Go Templates in Helm
When CRD specs contain Go templates (e.g., BootTarget.spec.template), use `.Files.Get` to avoid ugly escaping:

```yaml
# In templates/boottarget-foo.yaml
spec:
  template: |
{{ .Files.Get "files/boottarget-foo.tpl" | indent 4 }}
```

```
# In files/boottarget-foo.tpl (clean Go template syntax)
kernel http://{{ .Host }}:{{ .Port }}/iso/content/...
```

### CRD Validation
Use OpenAPI validation in CRDs:
- `minLength: 1` for required string fields
- `minProperties: 1` for required map fields
- `x-kubernetes-validations` for CEL rules (pattern matching, etc.)

### Deploy Status Phases
- `Pending` - Waiting for machine to PXE boot
- `InProgress` - Boot started, installation running
- `Completed` - Installation finished successfully
- `Failed` - Installation failed
- `ConfigError` - Missing referenced resources (self-heals when created)

## Testing

Test with QEMU PXE boot:
```bash
# Create disk
qemu-img create -f qcow2 /tmp/test.qcow2 20G

# Boot with PXE (UEFI)
sudo qemu-system-x86_64 \
  -enable-kvm -m 4096 -cpu host -smp 2 \
  -boot n \
  -drive file=/tmp/test.qcow2,format=qcow2 \
  -drive if=pflash,format=raw,readonly=on,file=/usr/share/OVMF/OVMF_CODE_4M.fd \
  -nic bridge,br=br1,model=virtio \
  -vnc :0 -daemonize
```

## Testing Go Code from Feature Branches

When testing isoboot-http from a feature branch (not merged to main), use GOPROXY=direct with the commit hash:

```bash
# Get the commit hash from the feature branch
git log --oneline feat/isoboot-http -1
# e.g., 41f7471 feat: add isoboot-http server

# Install directly from that commit (bypasses Go proxy cache)
GOPROXY=direct go install github.com/isoboot/isoboot/cmd/isoboot-http@41f7471
```

This approach:
- Avoids merging unreviewed code to main
- Bypasses the Go module proxy cache (which can take hours to update)
- Is explicit about which version is being tested

## Common Issues

- **Port 69 in use**: Another TFTP server is running. Remove it: `apt-get remove tftpd-hpa`
- **"no address range available"**: Subnet detection failed or dhcp-range is wrong
- **No proxy DHCP response**: Check dnsmasq logs with `kubectl logs <pod>`

## Commands

```bash
# Install
helm install isoboot . --set interface=br1

# Check logs
kubectl logs -f isoboot-isoboot-chart

# Reinstall (pod is immutable)
helm uninstall isoboot && helm install isoboot . --set interface=br1
```
