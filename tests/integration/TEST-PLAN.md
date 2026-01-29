# Integration Test Plan

Tests run in the `integration` GitHub Actions workflow against a kind cluster
with the Helm chart installed.

## 1. ISO Content Serving

Script: `tests/integration/iso-content/run.sh` (wrapper)
Per-image: `tests/integration/iso-content/test.sh <HOST_IP> <DISKIMAGE>`

Validates that the HTTP server correctly serves files extracted from ISOs,
and merges firmware into initrd when `includeFirmwarePath` is set on the BootTarget.

### 1.1 debian-12

#### 1.1.1 Error Handling

- [x] Invalid file path returns HTTP 404

#### 1.1.2 Kernel Serving

- [x] Kernel via no-firmware BootTarget matches kernel extracted from mini.iso (SHA-256)
- [x] Kernel via with-firmware BootTarget matches kernel extracted from mini.iso (SHA-256)

#### 1.1.3 Initrd Serving & Firmware Merging

- [x] Initrd via no-firmware BootTarget matches raw initrd.gz from mini.iso (SHA-256)
- [x] Initrd via with-firmware BootTarget differs from raw initrd.gz (firmware was merged)
- [x] Initrd via with-firmware BootTarget matches `cat initrd.gz firmware.cpio.gz` (SHA-256)

### 1.2 debian-13

#### 1.2.1 Error Handling

- [x] Invalid file path returns HTTP 404

#### 1.2.2 Kernel Serving

- [x] Kernel via no-firmware BootTarget matches kernel extracted from mini.iso (SHA-256)
- [x] Kernel via with-firmware BootTarget matches kernel extracted from mini.iso (SHA-256)

#### 1.2.3 Initrd Serving & Firmware Merging

- [x] Initrd via no-firmware BootTarget matches raw initrd.gz from mini.iso (SHA-256)
- [x] Initrd via with-firmware BootTarget differs from raw initrd.gz (firmware was merged)
- [x] Initrd via with-firmware BootTarget matches `cat initrd.gz firmware.cpio.gz` (SHA-256)

## 2. Boot Endpoints

### 2.1 iPXE Boot Script
- [x] boot.ipxe returns HTTP 200 with #!ipxe and conditional-boot chain URL

### 2.2 Conditional Boot Lifecycle
- [x] Returns 404 when no Provision exists
- [x] Returns 200 with debian-13-no-firmware after creating Provision
- [x] Returns 404 after /boot/done marks Provision Complete
- [x] Returns 200 with debian-12-with-firmware after creating second Provision

## 3. Answer File Rendering

- [ ] TODO

## 4. End-to-End Provisioning Flow

Script: `tests/integration/e2e/test.sh <HOST_IP>`

Full lifecycle test for debian-12-no-firmware: validates Provision status
transitions, content serving, and status invariants at every step.

### 4.1 Pre-provision
- [x] conditional-boot returns 404 before any Provision exists

### 4.2 Provision Creation
- [x] Create Provision, verify status is Pending

### 4.3 Wrong MAC
- [x] conditional-boot with unprovisioned MAC returns 404, status stays Pending

### 4.4 Boot Script
- [x] conditional-boot with correct MAC returns 200 with debian-12-no-firmware, status transitions to InProgress

### 4.5 Content Serving (status stays InProgress)
- [x] Kernel matches ISO (SHA-256), status InProgress
- [x] Initrd matches ISO (SHA-256), status InProgress
- [x] Preseed returns correct content, status InProgress

### 4.6 Completion
- [x] /boot/done returns 200, status transitions to Complete
- [x] conditional-boot returns 404 after done, status stays Complete
