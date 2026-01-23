# Milestones

## v0.1.0 - PXE Boot Infrastructure (Complete)

- Proxy DHCP with dnsmasq
- iPXE chainloading (BIOS + UEFI)
- Auto-detected subnet from interface

---

## v0.2.0 - Debian 13 Netboot (Next)

**Objective:** Boot to Debian 13 (trixie) installer screen with firmware support.

### Target Files

From Debian mirrors:
- **Mini ISO:** `https://deb.debian.org/debian/dists/trixie/main/installer-amd64/current/images/netboot/mini.iso`
- **Firmware:** `https://cdimage.debian.org/cdimage/firmware/trixie/current/firmware.cpio.gz`

### Technical Approach

1. **Extract from mini.iso:**
   - `linux` (kernel)
   - `initrd.gz` (initial ramdisk)

2. **Combine initrd with firmware:**
   ```bash
   cat initrd.gz firmware.cpio.gz > initrd-firmware.gz
   ```
   (initramfs is concatenated cpio archives - kernel extracts them in order)

3. **Serve via HTTP** (TFTP is too slow for large files)

4. **iPXE boot script:**
   ```ipxe
   #!ipxe
   kernel http://${server}/debian/linux
   initrd http://${server}/debian/initrd-firmware.gz
   boot
   ```

### New Components

#### isoboot-http
- HTTP server serving boot files
- Downloads and prepares Debian netboot files at startup
- Serves: kernel, combined initrd+firmware
- Simple nginx or Python HTTP server

#### isoboot-controller
- Orchestrates file preparation
- Downloads ISO and firmware
- Extracts kernel/initrd from ISO
- Combines initrd with firmware
- Generates iPXE boot script

### Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    isoboot pod                          │
├─────────────────┬─────────────────┬─────────────────────┤
│   dnsmasq       │  isoboot-http   │ isoboot-controller  │
│   (proxy DHCP)  │  (HTTP server)  │ (file prep)         │
│   port 67,4011  │  port 8080      │                     │
│   TFTP :69      │                 │                     │
└─────────────────┴─────────────────┴─────────────────────┘
         │                 │
         │ iPXE            │ kernel, initrd
         ▼                 ▼
    ┌─────────┐      ┌───────────┐
    │ PXE     │ ───► │ Debian    │
    │ Client  │      │ Installer │
    └─────────┘      └───────────┘
```

### Boot Flow

1. PXE client broadcasts DHCP discover
2. dnsmasq (proxy) responds with iPXE chainload
3. Client downloads iPXE via TFTP
4. iPXE executes boot script from HTTP
5. iPXE downloads kernel + initrd-firmware.gz via HTTP
6. Linux kernel boots into Debian installer

### Files to Create

```
isoboot-chart/
├── templates/
│   ├── pod.yaml              # Update: add http container
│   └── configmap.yaml        # iPXE boot script
├── images/
│   └── isoboot-controller/   # Dockerfile + scripts
└── values.yaml               # Add http port, debian version
```

### Open Questions

- [ ] Single pod with multiple containers vs separate pods?
- [ ] Persistent volume for downloaded files or ephemeral?
- [ ] How to detect/configure HTTP server IP for iPXE script?

---

## v0.3.0 - Custom Resource Definition (Future)

**Objective:** Declarative boot configuration via Kubernetes CRD.

### Concept

```yaml
apiVersion: isoboot.io/v1alpha1
kind: BootConfig
metadata:
  name: debian-13
spec:
  os: debian
  version: "13"
  arch: amd64
  firmware: true
  preseed:
    url: http://example.com/preseed.cfg
```

### Components

- **CRD:** `BootConfig` custom resource
- **Controller:** Watches BootConfig, generates iPXE scripts
- **Webhook:** Validates BootConfig specs

### Features

- Multiple OS support (Debian, Ubuntu, etc.)
- Preseed/autoinstall configuration
- Boot menu generation
- Per-machine boot assignment (MAC-based)

---

## Future Ideas

- v0.4.0: Ubuntu support
- v0.5.0: Boot menu with multiple OS options
- v0.6.0: Machine-specific boot configs (by MAC address)
- v0.7.0: Preseed/autoinstall integration
