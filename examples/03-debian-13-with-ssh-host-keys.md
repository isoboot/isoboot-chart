# Basic Debian 13 with SSH host key

1. Create the `Machine`.
```
kubectl apply -n isoboot -f - <<EOF
apiVersion: isoboot.io/v1alpha1
kind: Machine
metadata:
  name: vm-deb-13.lan
spec:
  mac: "52-54-00-26-10-13"
EOF
```

2. Create the `Secret`.
Please use any of these: `ssh_host_rsa_key`/`ssh_host_ecdsa_key`/`ssh_host_ed25519_key`. The public key is not neeeded, it will be generated.
```
kubectl apply -n isoboot -f - <<'EOF'
apiVersion: v1
kind: Secret
metadata:
  name: vm-deb-13-host-keys
type: Opaque
stringData:
  ssh_host_rsa_key: |
    -----BEGIN OPENSSH PRIVATE KEY-----
    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
    -----END OPENSSH PRIVATE KEY-----
  ssh_host_ecdsa_key: |
    -----BEGIN OPENSSH PRIVATE KEY-----
    b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAaAAAABNlY2RzYS
    1zaGEyLW5pc3RwMjU2AAAACG5pc3RwMjU2AAAAQQRivx/HrQBWUAIE8KVA4CYJOPFNFdaM
    vVH2zkg4aR1yP5R44z/kCoiv8MFIPD0MfN9ST224sldYiEq0j1WwfsD3AAAAqEoO9a1KDv
    WtAAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBGK/H8etAFZQAgTw
    pUDgJgk48U0V1oy9UfbOSDhpHXI/lHjjP+QKiK/wwUg8PQx831JPbbiyV1iISrSPVbB+wP
    cAAAAgf+TPND9zfRIq5BudzRm9gaTSQBDAlAItf+RbIfkf5UUAAAAOcm9vdEB2bS1kZWIt
    MTMBAg==
    -----END OPENSSH PRIVATE KEY-----
  ssh_host_ed25519_key: |
    -----BEGIN OPENSSH PRIVATE KEY-----
    b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW
    QyNTUxOQAAACCDEjxsNHlD6niO3gWMrerbf39QysDH0OqJgyK6IUhHDQAAAJhtkZDobZGQ
    6AAAAAtzc2gtZWQyNTUxOQAAACCDEjxsNHlD6niO3gWMrerbf39QysDH0OqJgyK6IUhHDQ
    AAAECFe4Yss2UyJ40nPXxAjJhLQIBxTR5eQcu5lCWAvcWRJIMSPGw0eUPqeI7eBYyt6tt/
    f1DKwMfQ6omDIrohSEcNAAAADnJvb3RAdm0tZGViLTEzAQIDBAUGBw==
    -----END OPENSSH PRIVATE KEY-----
EOF
```

3. Create the `ResponseTemplate`.
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
        echo "Processing SSH public key..." >> /target/root/late_command.log && \
      {{- if and (hasKey . "sshPublicKey") .sshPublicKey (hasKey . "username") .username }}
        in-target mkdir -p /home/{{ .username }}/.ssh && \
        in-target chmod 700 /home/{{ .username }}/.ssh && \
        echo '{{ .sshPublicKey }}' > /target/home/{{ .username }}/.ssh/authorized_keys && \
        in-target chmod 600 /home/{{ .username }}/.ssh/authorized_keys && \
        in-target chown -R {{ .username }}:{{ .username }} /home/{{ .username }}/.ssh && \
      {{- end }}
        echo "Processing SSH host keys..." >> /target/root/late_command.log && \
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
        wget -qO- http://{{ .Host }}:{{ .Port }}/dynamic/boot/done?mac={{ .MAC }} && \
        echo "Done." >> /target/root/late_command.log
EOF
```

4. Create the `ConfigMap`
Create the password
```
$ openssl passwd -6
Password:
Verifying - Password:
$6$5cyuuvFamWqaN22q$7xO0VNYubQtks2EmhH0wcBKtp0uafmd/1aH0bjccMtNL7i2z9v1mdAIZ9RHfa75RJ5ssOzm6lQn0/Mbkf068B.
```

Use the password and public key
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
  password: "$6$5cyuuvFamWqaN22q$7xO0VNYubQtks2EmhH0wcBKtp0uafmd/1aH0bjccMtNL7i2z9v1mdAIZ9RHfa75RJ5ssOzm6lQn0/Mbkf068B."
  timezone: "America/Los_Angeles"
  sshPublicKey: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIP9GAaptwDXjTCCJ4B0IFybongypdPGYwsD2ikYtO5ZL"
EOF
```

4. Link them all together in a `Provision`
```
kubectl apply -n isoboot -f - <<EOF
apiVersion: isoboot.io/v1alpha1
kind: Provision
metadata:
  name: vm-deb-13-with-firmware
spec:
  machineRef: vm-deb-13.lan
  bootTargetRef: debian-13-with-firmware
  responseTemplateRef: debian-standard-v1
  configMaps:
    - config-01
  secrets:
    - vm-deb-13-host-keys
EOF
```

5. Take a look at the deployment.
```
$ kubectl -n isoboot get provision
NAME                      MACHINE         BOOTTARGET                STATUS    IP    AGE
vm-deb-13-with-firmware   vm-deb-13.lan   debian-13-with-firmware   Pending         14s
```

6. Reboot the target machine

7. Shortly after it boots, the `STATUS` column will be updated from `Pending` to `InProgress`.
```
$ kubectl get provision -n isoboot
NAME                      MACHINE         BOOTTARGET                STATUS       IP    AGE
vm-deb-13-with-firmware   vm-deb-13.lan   debian-13-with-firmware   InProgress         76s
```

8. Finally, the `STATUS` column will be updated from `InProgress` to `Complete`. The `IP` address will be shown.
```
NAME                      MACHINE         BOOTTARGET                STATUS     IP               AGE
vm-deb-13-with-firmware   vm-deb-13.lan   debian-13-with-firmware   Complete   192.168.88.192   4m
```

9. You can remotely connect via SSH using the credentials you configured for this Debian installation (for example, the `isoboot` user created during setup).
```
ssh isoboot@192.168.88.192
```

## Why inject SSH host keys?

Without injected host keys, every fresh install generates random host keys. This means:
- SSH clients see a "host key has changed" warning when a machine is reinstalled
- There's no way to verify the machine's identity on first connection (TOFU problem)
- Automation scripts must use `StrictHostKeyChecking=no`, which is insecure

By injecting known host keys during provisioning, you can:
- Pre-populate `~/.ssh/known_hosts` on client machines before the target even boots
- Connect without the "Are you sure you want to continue connecting?" prompt
- Detect MITM attacks — if the host key doesn't match, SSH refuses to connect

## How to use injected host keys

Build `known_hosts` entries from the private keys used in the Secret:

```bash
for key_file in ssh_host_ed25519_key ssh_host_ecdsa_key ssh_host_rsa_key; do
  ssh-keygen -y -f /path/to/${key_file} | while read key_type key_data; do
    echo "192.168.88.192 ${key_type} ${key_data}"
  done
done >> ~/.ssh/known_hosts
```

Then SSH connects without prompting:
```
# No "Are you sure you want to continue connecting?" prompt
$ ssh isoboot@192.168.88.192
Linux vm-deb-13 ...
isoboot@vm-deb-13:~$
```

If the host key doesn't match (e.g., machine was compromised or reinstalled with different keys), SSH refuses:
```
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@    WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!     @
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
```
