# Debian 13 with Machine ID

This example demonstrates setting a consistent systemd machine-id during installation. This is useful for:
- Consistent host identification across reboots
- Predictable DHCP client IDs
- Stable /var/log/journal directories

## Steps

1. Create the `Machine`.
```
kubectl apply -n isoboot -f - <<EOF
apiVersion: isoboot.io/v1alpha1
kind: Machine
metadata:
  name: vm-04.lan
spec:
  mac: "52-54-00-00-00-04"
EOF
```

2. Create the `Secret` with SSH host keys.
The public keys will be auto-derived from the private keys.
```
kubectl apply -n isoboot -f - <<'EOF'
apiVersion: v1
kind: Secret
metadata:
  name: vm-04-host-keys
type: Opaque
stringData:
  ssh_host_ecdsa_key: |
    -----BEGIN OPENSSH PRIVATE KEY-----
    b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAaAAAABNlY2RzYS
    1zaGEyLW5pc3RwMjU2AAAACG5pc3RwMjU2AAAAQQQdxiFFJonkasB0j3baSH30yX1eeOtH
    jMtH8TCeaA+umuQ4vbUxW+L4Dklp7jQHqgzjexOCvxLrgfG3gtCon7itAAAAoEg4WBpIOF
    gaAAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBB3GIUUmieRqwHSP
    dtpIffTJfV5460eMy0fxMJ5oD66a5Di9tTFb4vgOSWnuNAeqDON7E4K/EuuB8beC0KifuK
    0AAAAgGueKNABGZMQeajObMljuUQ/EmPx++dBXonuMMS9XJ/MAAAAIcm9vdEB2bTE=
    -----END OPENSSH PRIVATE KEY-----
  ssh_host_ed25519_key: |
    -----BEGIN OPENSSH PRIVATE KEY-----
    b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW
    QyNTUxOQAAACAhftQ9IwUaPHjrI2t3nuwdJoIUH6l/8RTsjhgOzRxK8gAAAJCUvFyplLxc
    qQAAAAtzc2gtZWQyNTUxOQAAACAhftQ9IwUaPHjrI2t3nuwdJoIUH6l/8RTsjhgOzRxK8g
    AAAEA4OVQgo5nF+dt4a8G+GmeszD4sg/Ot1nWLFloTMSP2ayF+1D0jBRo8eOsja3ee7B0m
    ghQfqX/xFOyOGA7NHEryAAAACHJvb3RAdm0xAQIDBAU=
    -----END OPENSSH PRIVATE KEY-----
  ssh_host_rsa_key: |
    -----BEGIN OPENSSH PRIVATE KEY-----
    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
    d80VBtVd0f8c0AAAAIcm9vdEB2bTEBAgM=
    -----END OPENSSH PRIVATE KEY-----
EOF
```

3. Create the `ResponseTemplate`.
Note the use of `hasKey` to conditionally process the machine-id:
```
kubectl apply -n isoboot -f - <<'EOF'
apiVersion: isoboot.io/v1alpha1
kind: ResponseTemplate
metadata:
  name: debian-standard-v1
spec:
  files:
    preseed.cfg: |
      tasksel tasksel/first multiselect standard, ssh-server
      d-i debian-installer/language string {{ .language }}
      d-i debian-installer/country string {{ .country }}
      d-i keyboard-configuration/xkb-keymap select {{ .keyboard }}
      d-i passwd/root-login boolean {{ .loginAsRoot }}
      d-i passwd/user-fullname {{ .fullName }}
      d-i passwd/username string {{ .username }}
      d-i passwd/user-password-crypted password {{ .password }}
      d-i time/zone string {{ .timezone }}
      d-i partman-auto/method string regular
      d-i partman/choose_partition select finish
      d-i partman/confirm_nooverwrite boolean true
      d-i partman/confirm boolean true
      d-i finish-install/reboot_in_progress note
      d-i preseed/late_command string \
        echo "Processing SSH public key..." >> /target/root/late_command.log && \
      {{- if and (hasKey . "sshPublicKey") .sshPublicKey (hasKey . "username") .username }}
        in-target mkdir -p /home/{{ .username }}/.ssh && \
        in-target chmod 700 /home/{{ .username }}/.ssh && \
        echo '{{ .sshPublicKey }}' > /target/home/{{ .username }}/.ssh/authorized_keys && \
        in-target chmod 600 /home/{{ .username }}/.ssh/authorized_keys && \
        in-target chown -R {{ .username }}:{{ .username }} /home/{{ .username }}/.ssh && \
      {{- end }}
      {{- if hasKey . "MachineId" }}
        echo "Processing Machine Id..." >> /target/root/late_command.log && \
        echo '{{ .MachineId }}' > /target/etc/machine-id && \
        chmod 444 /target/etc/machine-id && \
      {{- end }}
      {{- if and (hasKey . "ssh_host_ed25519_key") (hasKey . "ssh_host_ed25519_key_pub") }}
        echo "Processing ssh_host_ed25519_key..." >> /target/root/late_command.log && \
        echo '{{ .ssh_host_ed25519_key | b64enc }}' | base64 -d > /target/etc/ssh/ssh_host_ed25519_key && \
        echo '{{ .ssh_host_ed25519_key_pub | b64enc }}' | base64 -d > /target/etc/ssh/ssh_host_ed25519_key.pub && \
        chmod 600 /target/etc/ssh/ssh_host_ed25519_key && \
        chmod 644 /target/etc/ssh/ssh_host_ed25519_key.pub && \
      {{- end }}
      {{- if and (hasKey . "ssh_host_ecdsa_key") (hasKey . "ssh_host_ecdsa_key_pub") }}
        echo "Processing ssh_host_ecdsa_key..." >> /target/root/late_command.log && \
        echo '{{ .ssh_host_ecdsa_key | b64enc }}' | base64 -d > /target/etc/ssh/ssh_host_ecdsa_key && \
        echo '{{ .ssh_host_ecdsa_key_pub | b64enc }}' | base64 -d > /target/etc/ssh/ssh_host_ecdsa_key.pub && \
        chmod 600 /target/etc/ssh/ssh_host_ecdsa_key && \
        chmod 644 /target/etc/ssh/ssh_host_ecdsa_key.pub && \
      {{- end }}
      {{- if and (hasKey . "ssh_host_rsa_key") (hasKey . "ssh_host_rsa_key_pub") }}
        echo "Processing ssh_host_rsa_key..." >> /target/root/late_command.log && \
        echo '{{ .ssh_host_rsa_key | b64enc }}' | base64 -d > /target/etc/ssh/ssh_host_rsa_key && \
        echo '{{ .ssh_host_rsa_key_pub | b64enc }}' | base64 -d > /target/etc/ssh/ssh_host_rsa_key.pub && \
        chmod 600 /target/etc/ssh/ssh_host_rsa_key && \
        chmod 644 /target/etc/ssh/ssh_host_rsa_key.pub && \
      {{- end }}
        wget -qO- http://{{ .Host }}:{{ .Port }}/dynamic/boot/done?mac={{ .MAC }} && \
        echo "Done." >> /target/root/late_command.log
EOF
```

4. Create the `ConfigMap`.

First, generate a password hash:
```
$ openssl passwd -6
Password:
Verifying - Password:
$6$a8NRCfAF9OAWdFlz$IqTgRAkK963GUr3AkpVc7SIyHAVxYk9V.Nx9vqsS87LnQga6O1u2lhLYJoRYX/ubL99YB1kn629XOh7aeExdN/
```

Then create the ConfigMap with the password and your SSH public key:
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

5. Create the `Provision` with `machineId`.

Generate a machine-id (32 lowercase hex characters):
```
$ cat /proc/sys/kernel/random/uuid | tr -d '-'
ca0a94d450b844f8bd13ad2fb02d9add
```

Create the Provision:
```
kubectl apply -n isoboot -f - <<EOF
apiVersion: isoboot.io/v1alpha1
kind: Provision
metadata:
  name: vm-04-debian-13
spec:
  machineRef: vm-04.lan
  bootTargetRef: debian-13-no-firmware
  responseTemplateRef: debian-standard-v1
  configMaps:
    - config-01
  machineId: ca0a94d450b844f8bd13ad2fb02d9add
  secrets:
    - vm-04-host-keys
EOF
```

6. Check the deployment status.
```
$ kubectl -n isoboot get provision
NAME              MACHINE      BOOTTARGET             STATUS    IP    AGE
vm-04-debian-13   vm-04.lan    debian-13-no-firmware  Pending         10s
```

7. Reboot the target machine to PXE boot.

8. The `STATUS` will change from `Pending` to `InProgress` when the boot script is served.
```
$ kubectl get provision -n isoboot
NAME              MACHINE      BOOTTARGET             STATUS       IP    AGE
vm-04-debian-13   vm-04.lan    debian-13-no-firmware  InProgress         60s
```

9. When installation completes, `STATUS` changes to `Complete` with the IP address.
```
$ kubectl get provision -n isoboot
NAME              MACHINE      BOOTTARGET             STATUS     IP               AGE
vm-04-debian-13   vm-04.lan    debian-13-no-firmware  Complete   192.168.88.104   5m
```

10. SSH into the machine and verify the machine-id was set:
```
$ ssh isoboot@192.168.88.104

$ cat /etc/machine-id
ca0a94d450b844f8bd13ad2fb02d9add
```

## Key Points

- **machineId format**: Must be exactly 32 lowercase hexadecimal characters
- **hasKey template function**: Use `{{ if hasKey . "MachineId" }}` to conditionally process the machine-id
- **Permissions**: The machine-id file should be read-only (444)
- **Persistence**: Once set, the machine-id remains constant across reboots
