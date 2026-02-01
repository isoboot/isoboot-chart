# Basic Debian 12

1. Create the `Machine`.
```
kubectl apply -n isoboot -f - <<EOF
apiVersion: isoboot.io/v1alpha1
kind: Machine
metadata:
  name: vm-deb-12.lan
spec:
  mac: "52-54-00-26-10-13"
EOF
```

2. Create the `ResponseTemplate`.
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
      d-i preseed/late_command string wget -qO- http://{{ .Host }}:{{ .Port }}/dynamic/boot/done?mac={{ .MAC }}
EOF
```

3. Create the `ConfigMap`
Create the password
```
$ openssl passwd -6 
Password: 
Verifying - Password: 
$6$5cyuuvFamWqaN22q$7xO0VNYubQtks2EmhH0wcBKtp0uafmd/1aH0bjccMtNL7i2z9v1mdAIZ9RHfa75RJ5ssOzm6lQn0/Mbkf068B.
```

Use the password
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
EOF
```

4. Link them all together in a `Provision`
```
kubectl apply -n isoboot -f - <<EOF
apiVersion: isoboot.io/v1alpha1
kind: Provision
metadata:
  name: vm-deb-12-no-firmware
spec:
  machineRef: vm-deb-12.lan
  bootTargetRef: debian-12-no-firmware
  responseTemplateRef: debian-standard-v1
  configMaps:
    - config-01
EOF
```

5. Take a look at the deployment.
```
$ kubectl -n isoboot get provision
NAME                    MACHINE         BOOTTARGET              STATUS    IP    AGE
vm-deb-12-no-firmware   vm-deb-12.lan   debian-12-no-firmware   Pending         9s
```

6. Reboot the target machine

7. Shortly after it boots, the `STATUS` column will be updated from `Pending` to `InProgress`.
```
$ kubectl get provision -n isoboot
NAME                    MACHINE         BOOTTARGET              STATUS       IP    AGE
vm-deb-12-no-firmware   vm-deb-12.lan   debian-12-no-firmware   InProgress         2m38s
```

8. Finally, the `STATUS` column will be updated from `InProgress` to `Complete`. The `IP` address will be shown.
```
$ kubectl get provision -n isoboot
NAME                    MACHINE         BOOTTARGET              STATUS     IP               AGE
vm-deb-12-no-firmware   vm-deb-12.lan   debian-12-no-firmware   Complete   192.168.88.192   5m35s
```

9. You can remotely connect via SSH using the credentials you configured for this Debian installation (for example, the `isoboot` user created during setup).
```
ssh isoboot@192.168.88.192
```
