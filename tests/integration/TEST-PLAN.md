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

## 2. Boot Script Rendering

- [ ] TODO

## 3. Answer File Rendering

- [ ] TODO

## 4. End-to-End Examples

### 4.1 Example 01 — Basic Debian 12

- [ ] TODO
