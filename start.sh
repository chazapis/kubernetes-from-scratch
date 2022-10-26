#!/bin/bash

# Copyright © 2022 Antony Chazapis
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

(cd cfssl && ./generate.sh)

# Generate the Data Encryption Config and Key
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

# Bootstrap etcd
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

# Bootstrap the Kubernetes Control Plane
IP_ADDRESS=`hostname -i`
kube-apiserver \
  --advertise-address=${IP_ADDRESS} \
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
  --service-account-issuer=https://${IP_ADDRESS}:6443 \
  --service-cluster-ip-range=10.32.0.0/24 \
  --service-node-port-range=30000-32767 \
  --tls-cert-file=/etc/kubernetes/ssl/kubernetes.pem \
  --tls-private-key-file=/etc/kubernetes/ssl/kubernetes-key.pem \
  &> /var/log/kubernetes/kube-apiserver.log &
kube-controller-manager \
  --bind-address=0.0.0.0 \
  --cluster-name=kubernetes \
  --cluster-signing-cert-file=/etc/kubernetes/ssl/ca.pem \
  --cluster-signing-key-file=/etc/kubernetes/ssl/ca-key.pem \
  --kubeconfig=/etc/kubernetes/kube-controller-manager.kubeconfig \
  --root-ca-file=/etc/kubernetes/ssl/ca.pem \
  --service-account-private-key-file=/etc/kubernetes/ssl/service-account-key.pem \
  --service-cluster-ip-range=10.32.0.0/24 \
  --use-service-account-credentials=true \
  &> /var/log/kubernetes/kube-controller-manager.log &

# Configure kubectl
mkdir -p ~/.kube
cp /etc/kubernetes/admin.kubeconfig ~/.kube/config
while ! kubectl version; do sleep 1; done

# Deploy the DNS service
mkdir -p /etc/coredns
cat > /etc/coredns/Corefile <<EOF
.:53 {
    errors
    kubernetes cluster.local in-addr.arpa ip6.arpa {
        endpoint 127.0.0.1:6443
        kubeconfig /root/.kube/config
        pods insecure
        fallthrough in-addr.arpa ip6.arpa
        ttl 5
    }
    forward . /etc/resolv.conf
    cache 30
    loop
    reload
    loadbalance
}
EOF
coredns -conf /etc/coredns/Corefile \
  &> /var/log/kubernetes/coredns.log &
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: kube-dns
  namespace: kube-system
spec:
  clusterIP: None
  ports:
  - name: dns
    port: 53
    protocol: UDP
  - name: dns-tcp
    port: 53
    protocol: TCP
---
apiVersion: v1
kind: Endpoints
metadata:
  name: kube-dns
  namespace: kube-system
subsets:
- addresses:
  - ip: ${IP_ADDRESS}
    nodeName: k8s-control
  ports:
  - name: dns
    port: 53
    protocol: UDP
  - name: dns-tcp
    port: 53
    protocol: TCP
EOF

# Start the random scheduler
if [ "$K8SFS_BUILTIN_SCHEDULER" == "1" ]; then
  random-scheduler \
    &> /var/log/kubernetes/random-scheduler.log &
fi

# Start the Virtual Kubelet
if [ "$K8SFS_BUILTIN_KUBELET" == "1" ]; then
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
fi

# Done
sleep infinity
