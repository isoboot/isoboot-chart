# TODO

## Debian Preseed Enhancements

- [x] **Add callback to mark provision as complete**
  - Endpoint: `GET /boot/done?id={machineName}`
  - Preseed: `d-i preseed/late_command string wget -qO- http://{{ .Host }}:{{ .Port }}/boot/done?id={{ .Hostname }} || true`

- [x] **Track completion IP in Provision status**
  - Capture IP when `/boot/done` is called
  - Store in Provision status and display as kubectl column
  - Helps verify completing machine matches expectations

- [x] **Configure Debian as console-only with SSH**
  - Preseed to install minimal system without desktop
  - `tasksel tasksel/first multiselect standard, ssh-server`

- [ ] **Support SSH authorized_keys per user**
  - Store SSH public keys in ConfigMap/Secret
  - Inject via late_command to `~/.ssh/authorized_keys`
  - Set correct permissions (700 for .ssh, 600 for authorized_keys)

- [ ] **Support injecting existing SSH host keys**
  - Store host keys in Secret
  - Inject via late_command to `/etc/ssh/ssh_host_*`
  - Avoids SSH known_hosts warnings after reinstall

## Ubuntu Support

- [ ] **Add support for Ubuntu reporting endpoint**
  - Ubuntu autoinstall can POST progress updates to webhook
  - Implement endpoint in isoboot-http to receive reports
  - Update Provision status based on installation progress
