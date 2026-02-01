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
- **After each commit pushed to a PR**, re-read the PR body (`gh pr view {n} --json body`) and update it if the summary no longer reflects the full set of changes. Use `gh pr edit {n} --body "..."` to update.
- **Copilot review is MANDATORY for every PR.** After creating a PR, run the full Copilot review loop before telling the user the PR is ready.

  **Step 1 — Request review:**
  ```bash
  gh api repos/{owner}/{repo}/pulls/{n}/requested_reviewers -X POST -f 'reviewers[]=copilot-pull-request-reviewer[bot]'
  ```

  **Step 2 — Wait for "started reviewing":**
  Poll the PR timeline every 15 seconds for up to 1 minute, looking for a Copilot review event (use `gh api repos/{owner}/{repo}/pulls/{n}/reviews`). If no review appears within 1 minute, re-request the review (back to Step 1). After 3 consecutive failures to get a review started, stop and inform the user.

  **Step 3 — Wait for review to complete:**
  Once a review exists, poll every 15 seconds until the review state is no longer `PENDING` (i.e., it becomes `COMMENTED`, `CHANGES_REQUESTED`, or `APPROVED`). Timeout: 10 minutes.

  **Step 4 — Handle comments:**
  Fetch all review comments (`gh api repos/{owner}/{repo}/pulls/{n}/comments`). For each comment:
  - **Addressable**: Fix the code, commit, push, reply inline referencing the commit, resolve the thread.
  - **Non-issue**: Reply inline explaining why, resolve the thread.
  - **Out of scope**: Create a GitHub issue, reply inline with "Tracked in #N", resolve the thread.

  **Step 5 — Loop if commits were pushed:**
  If Step 4 produced new commits, go back to Step 1 and repeat the entire loop. The goal is to reach a Copilot review with zero unresolved comments.

  **Step 6 — Done:**
  When Copilot returns `APPROVED` or `COMMENTED` with no comments, the review loop is complete. Report the PR URL to the user.

## Chart Overview

Deploys a PXE boot proxy DHCP server using dnsmasq and iPXE. Enables network booting without replacing your existing DHCP server.

## Architecture

- **Pod with hostNetwork**: Uses the host's network stack to bind to DHCP/TFTP ports
- **dnsmasq**: Runs in proxy DHCP mode - responds to PXE requests without handing out IP addresses
- **iPXE**: Boot files (undionly.kpxe for BIOS, ipxe.efi for UEFI) served via TFTP
- **nginx** (port 8080): External-facing reverse proxy. Serves `/static/` files from disk (including `boot.ipxe` generated at startup), proxies `/dynamic/*` to the Go server
- **isoboot-http** (port 80, ClusterIP Service): Go HTTP server. Handles conditional-boot, answer files, health checks. Nginx strips `/dynamic/` prefix and proxies to it via Service DNS

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
├── bootsource.yaml
├── boottarget.yaml
└── responsetemplate.yaml
templates/            # Kubernetes resources
├── _helpers.tpl
├── deployment-controller.yaml  # Deployment (auto-restart)
├── deployment-http.yaml        # Deployment (port 80, Go server)
├── deployment-nginx.yaml       # Deployment (hostNetwork:8080, reverse proxy)
├── deployment-squid.yaml       # Deployment (caching proxy)
├── pod-dnsmasq.yaml            # Pod (hostNetwork, DHCP/TFTP)
├── service-http.yaml           # ClusterIP Service (nginx → Go server)
├── rbac.yaml                   # ServiceAccount, Role, RoleBinding
├── configmap-templates.yaml    # ConfigMap for iPXE templates
├── bootsource-*.yaml           # BootSource resources (file downloads)
└── boottarget-*.yaml           # BootTarget resources (boot config)
files/                # Template files loaded via .Files.Get
└── boottarget-debian-v1.tpl
examples/             # Provisioning walkthrough examples
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
kernel http://{{ .Host }}:{{ .Port }}/static/{{ .BootSource }}/{{ .KernelFilename }}
```

### CRD Architecture: BootSource + BootTarget

- **BootSource** owns file downloads via named fields: `kernel`, `initrd` (direct URLs), or `iso` (ISO download + extraction with `iso.kernel`/`iso.initrd` paths). Optional `firmware` for initrd concatenation. One per OS version. Names: `debian-12`, `debian-13`.
- **BootTarget** references a BootSource via `bootSourceRef`. Adds `useFirmware: bool` and `template`. Multiple BootTargets can share one BootSource. Names: `debian-12-with-firmware`, `debian-12-no-firmware`.

BootSource directory layout without firmware (flat):
```
debian-12/
  linux       ← kernel
  initrd.gz   ← initrd
```

BootSource directory layout with firmware (subdirectories):
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
- `{{ .BootSource }}` - BootSource resource name (use for static file paths)
- `{{ .UseFirmware }}` - bool, whether to use firmware-combined initrd
- `{{ .ProvisionName }}` - Provision name (use for answer file URLs)
- `{{ .KernelFilename }}` - kernel filename (e.g., "linux")
- `{{ .InitrdFilename }}` - initrd filename (e.g., "initrd.gz")
- `{{ .HasFirmware }}` - bool, whether BootSource has firmware defined

Example iPXE template:
```
kernel http://{{ .Host }}:{{ .Port }}/static/{{ .BootSource }}/{{ .KernelFilename }}
initrd http://{{ .Host }}:{{ .Port }}/static/{{ .BootSource }}/with-firmware/{{ .InitrdFilename }}
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
- `WaitingForBootSource` - BootSource not yet Complete
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
kubectl logs -f deployment/isoboot-nginx

# Upgrade (deployments auto-restart)
helm upgrade isoboot . --set interface=br1

# Restart a deployment to pick up new code
kubectl rollout restart deployment/isoboot-controller
kubectl rollout restart deployment/isoboot-http

# Reinstall dnsmasq pod (still a pod, not deployment)
helm uninstall isoboot && helm install isoboot . --set interface=br1
```
