# CLAUDE.md

Helm chart for isoboot - PXE boot infrastructure on Kubernetes.

## Project Context

This repo works alongside `isoboot` (Go code for controller and HTTP server). Together they provide:
- **dnsmasq**: Proxy DHCP for PXE boot (this chart)
- **isoboot-controller**: Watches Provision CRs, manages boot workflows (Go repo)
- **isoboot-http**: Serves iPXE scripts, static files, answer files (Go repo)

## Git Conventions

- **Never force push** - use squash merge at PR merge time
- PRs required for main branch
- After merging a PR, delete the local branch (`git branch -d <branch>`). GitHub auto-deletes the remote branch on merge.
- On publishing a PR, request a Copilot review and poll for the response:
  ```bash
  # Request review
  gh api repos/{owner}/{repo}/pulls/{n}/requested_reviewers -X POST -f 'reviewers[]=copilot-pull-request-reviewer[bot]'
  ```
  Poll every 15 seconds for up to 10 minutes. If Copilot doesn't respond within 10 minutes, wait 5 minutes and re-request the review. After 3 consecutive failures, stop and inform the user.

  When Copilot leaves review comments, always reply inline on the thread, then resolve it:
  - **Addressable**: Fix in the next commit, reply inline referencing the commit, resolve the thread.
  - **Non-issue**: Reply inline explaining why, resolve the thread.
  - **Out of scope**: Create a GitHub issue, reply inline with "Tracked in #N", resolve the thread.

## Chart Overview

Deploys a PXE boot proxy DHCP server using dnsmasq and iPXE. Enables network booting without replacing your existing DHCP server.

## Architecture

- **Pod with hostNetwork**: Uses the host's network stack to bind to DHCP/TFTP ports
- **dnsmasq**: Runs in proxy DHCP mode - responds to PXE requests without handing out IP addresses
- **iPXE**: Boot files (undionly.kpxe for BIOS, ipxe.efi for UEFI) served via TFTP
- **nginx** (port 8080): External-facing reverse proxy. Serves `/static/` files from disk (including `boot.ipxe` generated at startup), proxies `/dynamic/*` to the Go server
- **isoboot-http** (127.0.0.1:8082): Go HTTP server, localhost-only. Handles conditional-boot, answer files, health checks. Nginx strips `/dynamic/` prefix and forwards to it

## Key Design Decisions

1. **hostNetwork over macvlan/multus**: We tried macvlan with Multus CNI but the CNI DHCP daemon couldn't properly access network namespaces from within a container. hostNetwork is simpler and works reliably.

2. **Runtime config generation**: The dnsmasq config is generated at pod startup (not via ConfigMap) to allow auto-detection of the subnet from the interface.

3. **Auto-detected subnet**: The pod extracts the network address from the interface IP using `ip` and `awk`, eliminating a required parameter.

4. **Alpine + runtime install**: Uses Alpine base image and installs dnsmasq/iproute2 at startup. This trades startup time for simpler maintenance (no custom image to build).

## File Structure

```
crds/                 # Custom Resource Definitions
├── machine.yaml
├── provision.yaml
├── bootmedia.yaml
├── boottarget.yaml
└── responsetemplate.yaml
templates/            # Kubernetes resources
├── _helpers.tpl
├── deployment-controller.yaml  # Deployment (auto-restart)
├── deployment-http.yaml        # Deployment (localhost:8082, Go server)
├── deployment-nginx.yaml       # Deployment (hostNetwork:8080, reverse proxy)
├── deployment-squid.yaml       # Deployment (hostNetwork, cached)
├── pod-dnsmasq.yaml            # Pod (hostNetwork, DHCP/TFTP)
├── bootmedia-*.yaml            # BootMedia resources (file downloads)
├── boottarget-*.yaml           # BootTarget resources (boot config)
└── ...
files/                # Template files loaded via .Files.Get
└── boottarget-debian-v1.tpl
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
kernel http://{{ .Host }}:{{ .Port }}/static/{{ .BootMedia }}/{{ .KernelFilename }}
```

### CRD Architecture: BootMedia + BootTarget

- **BootMedia** owns file downloads via named fields: `kernel`, `initrd` (direct URLs), or `iso` (ISO download + extraction with `iso.kernel`/`iso.initrd` paths). Optional `firmware` for initrd concatenation. One per OS version. Names: `debian-12`, `debian-13`.
- **BootTarget** references a BootMedia via `bootMediaRef`. Adds `useFirmware: bool` and `template`. Multiple BootTargets can share one BootMedia. Names: `debian-12`, `debian-12-no-firmware`.

BootMedia directory layout without firmware (flat):
```
debian-12/
  linux       ← kernel
  initrd.gz   ← initrd
```

BootMedia directory layout with firmware (subdirectories):
```
debian-12/
  linux                   ← kernel (always top-level)
  no-firmware/
    initrd.gz             ← original initrd
  with-firmware/
    initrd.gz             ← initrd + firmware.cpio.gz concatenated
```

### BootTarget Template Variables

Available in iPXE boot templates (files/boottarget-*.tpl):
- `{{ .Host }}` - HTTP server host IP
- `{{ .Port }}` - HTTP server port
- `{{ .MachineName }}` - full machine name (e.g., "vm-01.lan") - use for answer file URLs
- `{{ .Hostname }}` - first part before dot (e.g., "vm-01") - use for kernel hostname=
- `{{ .Domain }}` - everything after first dot (e.g., "lan") - use for kernel domain=
- `{{ .BootTarget }}` - BootTarget resource name
- `{{ .BootMedia }}` - BootMedia resource name (use for static file paths)
- `{{ .UseFirmware }}` - bool, whether to use firmware-combined initrd
- `{{ .ProvisionName }}` - Provision name (use for answer file URLs)
- `{{ .KernelFilename }}` - kernel filename (e.g., "linux")
- `{{ .InitrdFilename }}` - initrd filename (e.g., "initrd.gz")
- `{{ .HasFirmware }}` - bool, whether BootMedia has firmware defined

Example iPXE template:
```
kernel http://{{ .Host }}:{{ .Port }}/static/{{ .BootMedia }}/{{ .KernelFilename }}
initrd http://{{ .Host }}:{{ .Port }}/static/{{ .BootMedia }}/with-firmware/{{ .InitrdFilename }}
imgargs {{ .KernelFilename }} initrd={{ .InitrdFilename }} hostname={{ .Hostname }} domain={{ .Domain }} preseed/url=http://{{ .Host }}:{{ .Port }}/dynamic/answer/{{ .ProvisionName }}/preseed.cfg
boot
```

### CRD Validation
Use OpenAPI validation in CRDs:
- `minLength: 1` for required string fields
- `minProperties: 1` for required map fields
- `x-kubernetes-validations` for CEL rules (pattern matching, etc.)

### Provision Status Phases
- `Pending` - Waiting for machine to PXE boot
- `WaitingForBootMedia` - BootMedia not yet Complete
- `InProgress` - Boot started, installation running
- `Complete` - Installation finished successfully
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
kubectl logs -f deployment/isoboot-controller
kubectl logs -f deployment/isoboot-http

# Upgrade (deployments auto-restart)
helm upgrade isoboot . --set interface=br1

# Restart a deployment to pick up new code
kubectl rollout restart deployment/isoboot-controller
kubectl rollout restart deployment/isoboot-http

# Reinstall dnsmasq pod (still a pod, not deployment)
helm uninstall isoboot && helm install isoboot . --set interface=br1
```
