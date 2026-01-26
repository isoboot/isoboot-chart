# TODO

## Debian Preseed Enhancements

- [ ] **Add callback to mark deploy as complete**
  - Add `preseed/late_command` to call `POST /api/deploy/{machineName}/complete`
  - Marks Deploy status as Completed when installation finishes

- [ ] **Configure Debian as console-only with SSH**
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
  - Update Deploy status based on installation progress
