# Integration Test Plan

Tests run in the `integration` GitHub Actions workflow against a kind cluster
with the Helm chart installed.

## 1. Static Content Serving

Script: `tests/integration/iso-content/run.sh` (wrapper)
Per-BootSource: `tests/integration/iso-content/test.sh <HOST_IP> <BOOTSOURCE>`

Validates that the HTTP server correctly serves files downloaded by the
controller and stored at `/opt/isoboot/files/{bootSource}/`.

### 1.1 debian-12

- [x] Firmware expected (--expect-firmware flag fails test if no-firmware/ dir missing)
- [x] Invalid file path returns HTTP 404
- [x] Kernel served via /static/ matches downloaded file (SHA-256)
- [x] Initrd (no-firmware) served via /static/ matches downloaded file (SHA-256)
- [x] Initrd (with-firmware) served via /static/ matches downloaded file (SHA-256)
- [x] with-firmware initrd is larger than no-firmware initrd

### 1.2 debian-13

- [x] Firmware expected (--expect-firmware flag fails test if no-firmware/ dir missing)
- [x] Invalid file path returns HTTP 404
- [x] Kernel served via /static/ matches downloaded file (SHA-256)
- [x] Initrd (no-firmware) served via /static/ matches downloaded file (SHA-256)
- [x] Initrd (with-firmware) served via /static/ matches downloaded file (SHA-256)
- [x] with-firmware initrd is larger than no-firmware initrd

### 1.3 ISO Extraction Comparison (debian-13-iso)

Script: `tests/integration/iso-compare/test.sh <HOST_IP>`

Compares files from direct download (debian-13) vs ISO extraction (debian-13-iso)
to verify ISO extraction produces byte-identical output.

- [x] Kernel hash matches between direct download and ISO extraction
- [x] Initrd (no-firmware) hash matches between direct download and ISO extraction
- [x] Initrd (with-firmware) hash matches between direct download and ISO extraction

## 2. Boot Endpoints

### 2.1 Health Check
- [x] /dynamic/healthz returns HTTP 200

### 2.2 iPXE Boot Script
- [x] /static/boot.ipxe returns HTTP 200 with #!ipxe and conditional-boot chain URL

### 2.3 Conditional Boot Lifecycle
- [x] Returns 404 when no Provision exists
- [x] Returns 200 with debian-13 after creating Provision
- [x] Returns 404 after /dynamic/boot/done marks Provision Complete
- [x] Returns 200 with debian-12 after creating second Provision

## 3. Answer File Rendering

- [ ] TODO

## 4. End-to-End Provisioning Flow

Script: `tests/integration/e2e/test.sh <HOST_IP>`

Full lifecycle test for debian-12: validates Provision status
transitions, content serving, and status invariants at every step.

### 4.1 Pre-provision
- [x] conditional-boot returns 404 before any Provision exists

### 4.2 Provision Creation
- [x] Create Provision, verify status is Pending

### 4.3 Wrong MAC
- [x] conditional-boot with unprovisioned MAC returns 404, status stays Pending

### 4.4 Boot Script
- [x] conditional-boot with correct MAC returns 200 with debian-12, status transitions to InProgress

### 4.5 Content Serving (status stays InProgress)
- [x] Kernel matches downloaded file (SHA-256), status InProgress
- [x] Initrd (no-firmware) matches downloaded file (SHA-256), status InProgress
- [x] Preseed returns correct content, status InProgress

### 4.6 Completion
- [x] /dynamic/boot/done returns 200, status transitions to Complete
- [x] conditional-boot returns 404 after done, status stays Complete

## 5. PXE Install (Debian 13)

Script: `tests/integration/pxe-install/test.sh`
Workflow: `.github/workflows/pxe-install.yaml` (separate from the integration workflow)

Real PXE installation of Debian 13 (trixie) on a QEMU VM using an isolated
bridge network. Requires KVM; skips gracefully when unavailable.

### 5.1 Infrastructure
- [ ] Find unused subnet (192.168.101-199.0/24)
- [ ] Create bridge, NAT, host dnsmasq (regular DHCP)
- [ ] Create kind cluster, connect to bridge via veth
- [ ] Install CRDs + helm chart, wait for pods + BootSource Complete

### 5.2 Installation
- [ ] Generate credentials, create ConfigMap
- [ ] Apply Machine, ResponseTemplate, Provision
- [ ] QEMU VM PXE boots via UEFI (OVMF), installs Debian 13
- [ ] Provision transitions Pending -> InProgress -> Complete

### 5.3 Verification
- [ ] SSH to VM with generated credentials
- [ ] /etc/os-release contains VERSION_CODENAME=trixie
- [ ] Squid cache size increases (logged, not a hard gate)
- [ ] VM powers off cleanly
