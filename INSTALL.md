# Installation

## Kubernetes

### Tested on Ubuntu 24.04 raspi 5 8GB
```
sudo snap install microk8s --classic --channel=1.35/stable
sudo snap install kubectl --classic --channel=1.34/stable
sudo snap install helm --classic --channel=latest/stable
sudo usermod -aG microk8s $USER
```
You will need to logout after the `usermod` command.
```
mkdir ~/.kube
chmod 700 ~/.kube/
microk8s config > ~/.kube/config
kubectl version
```

## isoboot
The latest release is v0.5.0
```
mkdir isoboot
cd isoboot
git clone https://github.com/isoboot/isoboot-chart.git
cd isoboot-chart
git checkout v0.5.0
```

Install the helm chart
Please note to set the value of `INTERFACE` to a value from the `ip` command. For example `enp1s0`.
```
ip -4 -br address show
INTERFACE=???
helm uninstall isoboot -n isoboot 2>/dev/null || true && \
  kubectl delete namespace isoboot --ignore-not-found=true --wait && \
  kubectl get crd -o name | grep isoboot.io | xargs -r kubectl delete --ignore-not-found=true && \
  kubectl apply -f ./crds/ && \
  helm install isoboot . -n isoboot --create-namespace --set interface=${INTERFACE} && \
  kubectl wait --for=condition=ready pod --all -n isoboot --timeout=300s && \
  kubectl get pods -n isoboot
```
