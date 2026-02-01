# Debian 13 — Full Secure Provisioning

This example combines SSH key-only authentication, pre-injected SSH host keys, and a persistent machine-id into a single production-ready configuration.

- **SSH key-only auth** — password login disabled, only keypair authentication
- **Known host keys** — pre-injected host keys so clients can verify the machine's identity without TOFU (trust-on-first-use)
- **Persistent machine-id** — stable host identification across reboots for DHCP, journald, etc.

## Steps

1. Create the `Machine`.
```
kubectl apply -n isoboot -f - <<EOF
apiVersion: isoboot.io/v1alpha1
kind: Machine
metadata:
  name: vm-05.lan
spec:
  mac: "52-54-00-00-00-05"
EOF
```

2. Generate an SSH user keypair.
```
$ ssh-keygen -t ed25519 -f ~/.ssh/isoboot_ed25519 -N ""
Generating public/private ed25519 key pair.
Your identification has been saved in /home/user/.ssh/isoboot_ed25519
Your public key has been saved in /home/user/.ssh/isoboot_ed25519.pub
```

3. Create the `Secret` with SSH host keys.

Generate three key types (the public keys will be auto-derived from the private keys):
```
$ ssh-keygen -t ed25519 -f ssh_host_ed25519_key -N "" -C ""
$ ssh-keygen -t ecdsa -b 256 -f ssh_host_ecdsa_key -N "" -C ""
$ ssh-keygen -t rsa -b 4096 -f ssh_host_rsa_key -N "" -C ""
```

Create the Secret:
```
kubectl create secret generic vm-05-host-keys -n isoboot \
  --from-file=ssh_host_ed25519_key \
  --from-file=ssh_host_ecdsa_key \
  --from-file=ssh_host_rsa_key
```

4. Create the `ResponseTemplate`.

The `late_command` injects the SSH public key, host keys, machine-id, and disables password authentication:
```
kubectl apply -n isoboot -f - <<'EOF'
apiVersion: isoboot.io/v1alpha1
kind: ResponseTemplate
metadata:
  name: debian-secure-v1
spec:
  files:
    preseed.cfg: |
      tasksel tasksel/first multiselect standard, ssh-server
      d-i debian-installer/language string {{ .language }}
      d-i debian-installer/country string {{ .country }}
      d-i keyboard-configuration/xkb-keymap select {{ .keyboard }}
      d-i passwd/root-login boolean {{ .loginAsRoot }}
      d-i passwd/user-fullname string {{ .fullName }}
      d-i passwd/username string {{ .username }}
      d-i passwd/user-password-crypted password {{ .password }}
      d-i time/zone string {{ .timezone }}
      d-i partman-auto/method string regular
      d-i partman-auto/choose_recipe select atomic
      d-i partman/choose_partition select finish
      d-i partman/confirm_nooverwrite boolean true
      d-i partman/confirm boolean true
      d-i grub-installer/only_debian boolean true
      d-i finish-install/reboot_in_progress note
      d-i preseed/late_command string \
      {{- if and (hasKey . "sshPublicKey") .sshPublicKey (hasKey . "username") .username }}
        in-target mkdir -p /home/{{ .username }}/.ssh && \
        in-target chmod 700 /home/{{ .username }}/.ssh && \
        echo '{{ .sshPublicKey }}' > /target/home/{{ .username }}/.ssh/authorized_keys && \
        in-target chmod 600 /home/{{ .username }}/.ssh/authorized_keys && \
        in-target chown -R {{ .username }}:{{ .username }} /home/{{ .username }}/.ssh && \
      {{- end }}
      {{- if and (hasKey . "ssh_host_ed25519_key") (hasKey . "ssh_host_ed25519_key_pub") }}
        echo '{{ .ssh_host_ed25519_key | b64enc }}' | base64 -d > /target/etc/ssh/ssh_host_ed25519_key && \
        echo '{{ .ssh_host_ed25519_key_pub | b64enc }}' | base64 -d > /target/etc/ssh/ssh_host_ed25519_key.pub && \
        chmod 600 /target/etc/ssh/ssh_host_ed25519_key && \
        chmod 644 /target/etc/ssh/ssh_host_ed25519_key.pub && \
      {{- end }}
      {{- if and (hasKey . "ssh_host_ecdsa_key") (hasKey . "ssh_host_ecdsa_key_pub") }}
        echo '{{ .ssh_host_ecdsa_key | b64enc }}' | base64 -d > /target/etc/ssh/ssh_host_ecdsa_key && \
        echo '{{ .ssh_host_ecdsa_key_pub | b64enc }}' | base64 -d > /target/etc/ssh/ssh_host_ecdsa_key.pub && \
        chmod 600 /target/etc/ssh/ssh_host_ecdsa_key && \
        chmod 644 /target/etc/ssh/ssh_host_ecdsa_key.pub && \
      {{- end }}
      {{- if and (hasKey . "ssh_host_rsa_key") (hasKey . "ssh_host_rsa_key_pub") }}
        echo '{{ .ssh_host_rsa_key | b64enc }}' | base64 -d > /target/etc/ssh/ssh_host_rsa_key && \
        echo '{{ .ssh_host_rsa_key_pub | b64enc }}' | base64 -d > /target/etc/ssh/ssh_host_rsa_key.pub && \
        chmod 600 /target/etc/ssh/ssh_host_rsa_key && \
        chmod 644 /target/etc/ssh/ssh_host_rsa_key.pub && \
      {{- end }}
      {{- if hasKey . "MachineId" }}
        echo '{{ .MachineId }}' > /target/etc/machine-id && \
        chmod 444 /target/etc/machine-id && \
      {{- end }}
        in-target sed -i 's/^#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config && \
        in-target sed -i 's/^PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config && \
        wget -qO- http://{{ .Host }}:{{ .Port }}/dynamic/boot/done?mac={{ .MAC }}
EOF
```

5. Create the `ConfigMap`.

Generate a password hash:
```
$ openssl passwd -6
Password:
Verifying - Password:
$6$a8NRCfAF9OAWdFlz$IqTgRAkK963GUr3AkpVc7SIyHAVxYk9V.Nx9vqsS87LnQga6O1u2lhLYJoRYX/ubL99YB1kn629XOh7aeExdN/
```

Create the ConfigMap with the password and your SSH public key:
```
kubectl apply -n isoboot -f - <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: config-01
data:
  language: "en"
  country: "US"
  keyboard: "us"
  loginAsRoot: "false"
  fullName: "isoboot"
  username: "isoboot"
  password: "$6$a8NRCfAF9OAWdFlz$IqTgRAkK963GUr3AkpVc7SIyHAVxYk9V.Nx9vqsS87LnQga6O1u2lhLYJoRYX/ubL99YB1kn629XOh7aeExdN/"
  timezone: "America/Los_Angeles"
  sshPublicKey: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPc9nTIJPoXHj9+SIkOWnGIAwgtsjgAVA9pGCUIZIMIR"
EOF
```

6. Generate a machine-id.
```
$ dbus-uuidgen
ca0a94d450b844f8bd13ad2fb02d9add
```

7. Create the `Provision` linking everything together.
```
kubectl apply -n isoboot -f - <<EOF
apiVersion: isoboot.io/v1alpha1
kind: Provision
metadata:
  name: vm-05-debian-13-secure
spec:
  machineRef: vm-05.lan
  bootTargetRef: debian-13-no-firmware
  responseTemplateRef: debian-secure-v1
  configMaps:
    - config-01
  secrets:
    - vm-05-host-keys
  machineId: ca0a94d450b844f8bd13ad2fb02d9add
EOF
```

8. Check the deployment status.
```
$ kubectl -n isoboot get provision
NAME                     MACHINE     BOOTTARGET             STATUS    IP    AGE
vm-05-debian-13-secure   vm-05.lan   debian-13-no-firmware  Pending         10s
```

9. Reboot the target machine to PXE boot.

10. The `STATUS` will change from `Pending` to `InProgress` when the boot script is served.
```
$ kubectl get provision -n isoboot
NAME                     MACHINE     BOOTTARGET             STATUS       IP    AGE
vm-05-debian-13-secure   vm-05.lan   debian-13-no-firmware  InProgress         60s
```

11. When installation completes, `STATUS` changes to `Complete` with the IP address.
```
$ kubectl get provision -n isoboot
NAME                     MACHINE     BOOTTARGET             STATUS     IP               AGE
vm-05-debian-13-secure   vm-05.lan   debian-13-no-firmware  Complete   192.168.88.105   5m
```

## Verification

### Password auth is rejected

```
$ ssh -o PreferredAuthentications=password isoboot@192.168.88.105
isoboot@192.168.88.105: Permission denied (publickey).
```

### Key auth with known host keys succeeds immediately

First, add the host keys to `known_hosts`:
```bash
for key_file in ssh_host_ed25519_key ssh_host_ecdsa_key ssh_host_rsa_key; do
  ssh-keygen -y -f /path/to/${key_file} | while read key_type key_data; do
    echo "192.168.88.105 ${key_type} ${key_data}"
  done
done >> ~/.ssh/known_hosts
```

Then connect — no prompts, straight to shell:
```
$ ssh -i ~/.ssh/isoboot_ed25519 isoboot@192.168.88.105
Linux vm-05 ...
isoboot@vm-05:~$
```

There is no "Are you sure you want to continue connecting?" prompt because the host keys are pre-trusted. There is no password prompt because password auth is disabled and the key is accepted. If the machine were compromised or reinstalled with different keys, SSH would refuse the connection.

## Why this matters

- **Defense against reinstall confusion**: Known host keys mean SSH clients won't accept a different machine impersonating this one
- **Automation-friendly**: Scripts can connect without `-o StrictHostKeyChecking=no` (which is insecure in production)
- **Consistent identity**: machine-id ensures the host has a stable identifier for DHCP leases, systemd journal, and fleet management
- **Reduced attack surface**: Password auth disabled means brute-force SSH attacks are not possible
