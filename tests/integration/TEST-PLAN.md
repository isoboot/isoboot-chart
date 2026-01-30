# Integration Test Plan

Tests run in the `integration` GitHub Actions workflow against a kind cluster
with the Helm chart installed.

## 1. Static Content Serving

Script: `tests/integration/iso-content/run.sh` (wrapper)
Per-BootTarget: `tests/integration/iso-content/test.sh <HOST_IP> <BOOTTARGET>`

Validates that the HTTP server correctly serves files downloaded by the
controller and stored at `/opt/isoboot/files/{bootTarget}/`.

### 1.1 debian-12

- [x] firmware.cpio.gz must exist (--expect-firmware flag fails test if missing)
- [x] Invalid file path returns HTTP 404
- [x] Kernel served via /static/ matches downloaded file (SHA-256)
- [x] Initrd served via /static/ matches downloaded file (SHA-256)
- [x] firmware-initrd.gz served via /static/ matches combined file (SHA-256)
- [x] firmware-initrd.gz is larger than firmware alone

### 1.2 debian-13

- [x] firmware.cpio.gz must exist (--expect-firmware flag fails test if missing)
- [x] Invalid file path returns HTTP 404
- [x] Kernel served via /static/ matches downloaded file (SHA-256)
- [x] Initrd served via /static/ matches downloaded file (SHA-256)
- [x] firmware-initrd.gz served via /static/ matches combined file (SHA-256)
- [x] firmware-initrd.gz is larger than firmware alone

## 2. Boot Endpoints

### 2.1 Health Check
- [x] /dynamic/healthz returns HTTP 200

### 2.2 iPXE Boot Script
- [x] /dynamic/boot/boot.ipxe returns HTTP 200 with #!ipxe and conditional-boot chain URL

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
- [x] Initrd matches downloaded file (SHA-256), status InProgress
- [x] Preseed returns correct content, status InProgress

### 4.6 Completion
- [x] /dynamic/boot/done returns 200, status transitions to Complete
- [x] conditional-boot returns 404 after done, status stays Complete
