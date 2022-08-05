#!/bin/bash

(cd cfssl && ./generate.sh)

# Generating the Data Encryption Config and Key

ENCRYPTION_KEY=$(head -c 32 /dev/urandom | base64)
mkdir -p /etc/kubernetes
cat > /etc/kubernetes/encryption-config.yaml <<EOF
kind: EncryptionConfig
apiVersion: v1
resources:
  - resources:
      - secrets
    providers:
      - aescbc:
          keys:
            - name: key1
              secret: ${ENCRYPTION_KEY}
      - identity: {}
EOF

# Bootstrapping etcd

export ETCD_UNSUPPORTED_ARCH=arm64
mkdir -p /var/lib/kubernetes/etcd
mkdir -p /var/log/kubernetes

etcd \
  --cert-file=/etc/kubernetes/ssl/kubernetes.pem \
  --key-file=/etc/kubernetes/ssl/kubernetes-key.pem \
  --trusted-ca-file=/etc/kubernetes/ssl/ca.pem \
  --client-cert-auth \
  --listen-client-urls https://127.0.0.1:2379 \
  --advertise-client-urls https://127.0.0.1:2379 \
  --data-dir=/var/lib/kubernetes/etcd \
  &> /var/log/kubernetes/etcd.log &

# Verify with:
# etcdctl member list \
#   --endpoints=https://127.0.0.1:2379 \
#   --cacert=/etc/kubernetes/ssl/ca.pem \
#   --cert=/etc/kubernetes/ssl/kubernetes.pem \
#   --key=/etc/kubernetes/ssl/kubernetes-key.pem

# Bootstrapping the Kubernetes Control Plane

KUBERNETES_PUBLIC_ADDRESS=127.0.0.1

kube-apiserver \
  --allow-privileged=true \
  --authorization-mode=Node,RBAC \
  --bind-address=0.0.0.0 \
  --client-ca-file=/etc/kubernetes/ssl/ca.pem \
  --enable-admission-plugins=NamespaceLifecycle,NodeRestriction,LimitRanger,ServiceAccount,DefaultStorageClass,ResourceQuota \
  --etcd-cafile=/etc/kubernetes/ssl/ca.pem \
  --etcd-certfile=/etc/kubernetes/ssl/kubernetes.pem \
  --etcd-keyfile=/etc/kubernetes/ssl/kubernetes-key.pem \
  --etcd-servers=https://127.0.0.1:2379 \
  --encryption-provider-config=/etc/kubernetes/encryption-config.yaml \
  --kubelet-certificate-authority=/etc/kubernetes/ssl/ca.pem \
  --kubelet-client-certificate=/etc/kubernetes/ssl/kubernetes.pem \
  --kubelet-client-key=/etc/kubernetes/ssl/kubernetes-key.pem \
  --runtime-config='api/all=true' \
  --service-account-key-file=/etc/kubernetes/ssl/service-account.pem \
  --service-account-signing-key-file=/etc/kubernetes/ssl/service-account-key.pem \
  --service-account-issuer=https://${KUBERNETES_PUBLIC_ADDRESS}:6443 \
  --service-cluster-ip-range=10.32.0.0/24 \
  --service-node-port-range=30000-32767 \
  --tls-cert-file=/etc/kubernetes/ssl/kubernetes.pem \
  --tls-private-key-file=/etc/kubernetes/ssl/kubernetes-key.pem \
  &> /var/log/kubernetes/kube-apiserver.log &

kube-controller-manager \
  --bind-address=0.0.0.0 \
  --cluster-cidr=10.200.0.0/16 \
  --cluster-name=kubernetes \
  --cluster-signing-cert-file=/etc/kubernetes/ssl/ca.pem \
  --cluster-signing-key-file=/etc/kubernetes/ssl/ca-key.pem \
  --kubeconfig=/etc/kubernetes/kube-controller-manager.kubeconfig \
  --root-ca-file=/etc/kubernetes/ssl/ca.pem \
  --service-account-private-key-file=/etc/kubernetes/ssl/service-account-key.pem \
  --service-cluster-ip-range=10.32.0.0/24 \
  --use-service-account-credentials=true \
  &> /var/log/kubernetes/kube-controller-manager.log &

# Configuring kubectl

mkdir -p ~/.kube
cp /etc/kubernetes/admin.kubeconfig ~/.kube/config
# Verify with:
# kubectl version

# Start the random scheduler

random-scheduler \
  &> /var/log/kubernetes/random-scheduler.log &

# Start the Virtual Kubelet

cat > /etc/kubernetes/mock-config.json <<EOF
{
  "worker": {
    "cpu": "2",
    "memory": "32Gi",
    "pods": "128"
  }
}
EOF

# XXX Should adjust permissions to use worker credentials...
export KUBECONFIG=/etc/kubernetes/admin.kubeconfig
export APISERVER_KEY_LOCATION=/etc/kubernetes/ssl/admin-key.pem
export APISERVER_CERT_LOCATION=/etc/kubernetes/ssl/admin.pem

virtual-kubelet --disable-taint --nodename worker --provider mock --provider-config /etc/kubernetes/mock-config.json \
  &> /var/log/kubernetes/virtual-kubelet.log &

# Done

sleep infinity
