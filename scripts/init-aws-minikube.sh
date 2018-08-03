#!/bin/bash

# to install do the following:
# KUBEADM_TOKEN=$(kubeadm token generate)
# ssh $machine_ip /bin/bash =c "export kubeadm_token=$KUBEADM_TOKEN; curl -O /tmp/init-aws-minikube.sh https://raw.githubusercontent.com/bnouvelbmll/terraform-aws-minikube/bmll/scripts/init-aws-minikube.sh && sudo /tmp/init-aws-minikube.sh && rm -f /tmp/init-aws-minikube.sh"


set -o verbose
set -o errexit
set -o pipefail

export KUBEADM_TOKEN=${kubeadm_token}
export IP_ADDRESS="$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)""
export CLUSTER_NAME="bmll-compliance"
export DNS_NAME="compliance-minikube.bmll-privatenetwork"
export ADDONS=$(
cat << EOF
https://raw.githubusercontent.com/scholzj/terraform-aws-minikube/master/addons/storage-class.yaml
https://raw.githubusercontent.com/scholzj/terraform-aws-minikube/master/addons/heapster.yaml
https://raw.githubusercontent.com/scholzj/terraform-aws-minikube/master/addons/dashboard.yaml
EOF
)

export KUBERNETES_VERSION="1.10.6"

# Set this only after setting the defaults
set -o nounset

# We needed to match the hostname expected by kubeadm an the hostname used by kubelet
FULL_HOSTNAME="$(curl -s http://169.254.169.254/latest/meta-data/hostname)"

# Make DNS lowercase
DNS_NAME=$(echo "$DNS_NAME" | tr 'A-Z' 'a-z')

# Install docker
yum install -y yum-utils curl gettext device-mapper-persistent-data lvm2
yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
yum makecache fast
yum install -y docker-ce

# Install Kubernetes components
sudo cat <<EOF > /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-x86_64
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg
        https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
EOF

# setenforce returns non zero if already SE Linux is already disabled
is_enforced=$(getenforce)
if [[ $is_enforced != "Disabled" ]]; then
  setenforce 0
fi

yum install -y kubelet-$KUBERNETES_VERSION kubeadm-$KUBERNETES_VERSION kubernetes-cni

# Fix kubelet configuration
sed -i 's/--cgroup-driver=systemd/--cgroup-driver=cgroupfs/g' /etc/systemd/system/kubelet.service.d/10-kubeadm.conf
sed -i '/Environment="KUBELET_CGROUP_ARGS/i Environment="KUBELET_CLOUD_ARGS=--cloud-provider=aws"' /etc/systemd/system/kubelet.service.d/10-kubeadm.conf
sed -i 's/$KUBELET_CGROUP_ARGS/$KUBELET_CLOUD_ARGS $KUBELET_CGROUP_ARGS/g' /etc/systemd/system/kubelet.service.d/10-kubeadm.conf

# Start services
systemctl enable docker
systemctl start docker
systemctl enable kubelet
systemctl start kubelet

# Set settings needed by Docker
sysctl net.bridge.bridge-nf-call-iptables=1
sysctl net.bridge.bridge-nf-call-ip6tables=1

# Initialize the master
cat >/tmp/kubeadm.yaml <<EOF
---
apiVersion: kubeadm.k8s.io/v1alpha1
kind: MasterConfiguration
nodeName: $FULL_HOSTNAME
token: $KUBEADM_TOKEN
tokenTTL: "0"
cloudProvider: aws
kubernetesVersion: v$KUBERNETES_VERSION
apiServerCertSANs:
- $DNS_NAME
- $IP_ADDRESS
EOF

kubeadm reset
kubeadm init --config /tmp/kubeadm.yaml
rm /tmp/kubeadm.yaml

# Use the local kubectl config for further kubectl operations
export KUBECONFIG=/etc/kubernetes/admin.conf




# Install calico
wget -O /tmp/calico.yaml -nd https://raw.githubusercontent.com/bnouvelbmll/terraform-aws-minikube/bmll/scripts/calico.yaml
kubectl apply -f /tmp/calico.yaml

# Allow all apps to run on master
kubectl taint nodes --all node-role.kubernetes.io/master-

# Allow load balancers to route to master
kubectl label nodes --all node-role.kubernetes.io/master-

# Allow the user to administer the cluster
kubectl create clusterrolebinding admin-cluster-binding --clusterrole=cluster-admin --user=admin

# Prepare the kubectl config file for download to client (DNS)
export KUBECONFIG_OUTPUT=/home/centos/kubeconfig
kubeadm alpha phase kubeconfig user \
  --client-name admin \
  --apiserver-advertise-address $DNS_NAME \
  > $KUBECONFIG_OUTPUT
chown $USER:sysadmin $KUBECONFIG_OUTPUT
chmod 0640 $KUBECONFIG_OUTPUT

# Prepare the kubectl config file for download to client (IP address)
export KUBECONFIG_OUTPUT=/home/centos/kubeconfig_ip
kubeadm alpha phase kubeconfig user \
  --client-name admin \
  --apiserver-advertise-address $IP_ADDRESS \
  > $KUBECONFIG_OUTPUT
chown $USER:sysadmin $KUBECONFIG_OUTPUT
chmod 0640 $KUBECONFIG_OUTPUT

# Load addons
for ADDON in $ADDONS
do
  curl $ADDON | envsubst > /tmp/addon.yaml
  kubectl apply -f /tmp/addon.yaml
  rm /tmp/addon.yaml
done
