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

K8SFS_CFSSL_DIR=/var/local/kubernetes/cfssl
K8SFS_CONF_DIR=/usr/local/etc/kubernetes
K8SFS_DATA_DIR=/var/lib/kubernetes/etcd
K8SFS_LOG_DIR=/var/log/kubernetes

# Generate necessary keys
export IP_ADDRESS=`hostname -i`
(cd ${K8SFS_CFSSL_DIR} && ./generate.sh)
mkdir -p ${K8SFS_CONF_DIR}/ssl
(cd ${K8SFS_CFSSL_DIR} && \
  mv *.pem ${K8SFS_CONF_DIR}/ssl/ && \
  mv *.kubeconfig ${K8SFS_CONF_DIR} && \
  rm *.csr)

# Generate the data encryption config and key
ENCRYPTION_KEY=$(head -c 32 /dev/urandom | base64)
mkdir -p ${K8SFS_CONF_DIR}
cat > ${K8SFS_CONF_DIR}/encryption-config.yaml <<EOF
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
mkdir -p ${K8SFS_DATA_DIR}
chmod 700 ${K8SFS_DATA_DIR}
mkdir -p ${K8SFS_LOG_DIR}
etcd \
  --cert-file=${K8SFS_CONF_DIR}/ssl/kubernetes.pem \
  --key-file=${K8SFS_CONF_DIR}/ssl/kubernetes-key.pem \
  --trusted-ca-file=${K8SFS_CONF_DIR}/ssl/ca.pem \
  --client-cert-auth \
  --listen-client-urls https://127.0.0.1:2379 \
  --advertise-client-urls https://127.0.0.1:2379 \
  --data-dir=${K8SFS_DATA_DIR} \
  &> ${K8SFS_LOG_DIR}/etcd.log &

# Bootstrap the Kubernetes control plane
kube-apiserver \
  --advertise-address=${IP_ADDRESS} \
  --allow-privileged=true \
  --authorization-mode=Node,RBAC \
  --bind-address=0.0.0.0 \
  --client-ca-file=${K8SFS_CONF_DIR}/ssl/ca.pem \
  --enable-admission-plugins=NamespaceLifecycle,NodeRestriction,LimitRanger,ServiceAccount,DefaultStorageClass,ResourceQuota \
  --etcd-cafile=${K8SFS_CONF_DIR}/ssl/ca.pem \
  --etcd-certfile=${K8SFS_CONF_DIR}/ssl/kubernetes.pem \
  --etcd-keyfile=${K8SFS_CONF_DIR}/ssl/kubernetes-key.pem \
  --etcd-servers=https://127.0.0.1:2379 \
  --encryption-provider-config=${K8SFS_CONF_DIR}/encryption-config.yaml \
  --kubelet-certificate-authority=${K8SFS_CONF_DIR}/ssl/ca.pem \
  --kubelet-client-certificate=${K8SFS_CONF_DIR}/ssl/kubernetes.pem \
  --kubelet-client-key=${K8SFS_CONF_DIR}/ssl/kubernetes-key.pem \
  --runtime-config='api/all=true' \
  --service-account-key-file=${K8SFS_CONF_DIR}/ssl/service-account.pem \
  --service-account-signing-key-file=${K8SFS_CONF_DIR}/ssl/service-account-key.pem \
  --service-account-issuer=https://${IP_ADDRESS}:6443 \
  --service-cluster-ip-range=10.32.0.0/24 \
  --service-node-port-range=30000-32767 \
  --tls-cert-file=${K8SFS_CONF_DIR}/ssl/kubernetes.pem \
  --tls-private-key-file=${K8SFS_CONF_DIR}/ssl/kubernetes-key.pem \
  &> ${K8SFS_LOG_DIR}/kube-apiserver.log &
kube-controller-manager \
  --bind-address=0.0.0.0 \
  --cluster-name=kubernetes \
  --cluster-signing-cert-file=${K8SFS_CONF_DIR}/ssl/ca.pem \
  --cluster-signing-key-file=${K8SFS_CONF_DIR}/ssl/ca-key.pem \
  --kubeconfig=${K8SFS_CONF_DIR}/kube-controller-manager.kubeconfig \
  --root-ca-file=${K8SFS_CONF_DIR}/ssl/ca.pem \
  --service-account-private-key-file=${K8SFS_CONF_DIR}/ssl/service-account-key.pem \
  --service-cluster-ip-range=10.32.0.0/24 \
  --use-service-account-credentials=true \
  &> ${K8SFS_LOG_DIR}/kube-controller-manager.log &

# Configure kubectl
mkdir -p ~/.kube
cp ${K8SFS_CONF_DIR}/admin.kubeconfig ~/.kube/config
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
  &> ${K8SFS_LOG_DIR}/coredns.log &
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

# Start the services webhook
if [ "$K8SFS_HEADLESS_SERVICES" == "1" ]; then
    CA_BUNDLE=$(cat ${K8SFS_CONF_DIR}/ssl/ca.pem | base64 | tr -d '\n')
    cat <<EOF | kubectl apply -f -
apiVersion: admissionregistration.k8s.io/v1
kind: MutatingWebhookConfiguration
metadata:
  name: services-webhook
  namespace: default
webhooks:
  - name: services-webhook.default.svc
    clientConfig:
      url: "https://127.0.0.1:8443/mutate"
      caBundle: ${CA_BUNDLE}
    rules:
      - operations: ["CREATE", "UPDATE"]
        apiGroups: ["*"]
        apiVersions: ["*"]
        resources: ["services"]
        scope: "*"
    admissionReviewVersions: ["v1"]
    sideEffects: None
    failurePolicy: Fail
EOF

    services-webhook \
      -tlsCertFile ${K8SFS_CONF_DIR}/ssl/kubernetes.pem \
      -tlsKeyFile ${K8SFS_CONF_DIR}/ssl/kubernetes-key.pem \
      &> ${K8SFS_LOG_DIR}/services-webhook.log &
fi

# Start the random scheduler
if [ "$K8SFS_RANDOM_SCHEDULER" == "1" ]; then
    random-scheduler \
      &> ${K8SFS_LOG_DIR}/random-scheduler.log &
fi

# Start the Virtual Kubelet
if [ "$K8SFS_MOCK_KUBELET" == "1" ]; then
    cat > ${K8SFS_CONF_DIR}/mock-config.json <<EOF
{
    "worker": {
        "cpu": "2",
        "memory": "32Gi",
        "pods": "128"
    }
}
EOF

    # XXX Should adjust permissions to use worker credentials...
    export KUBECONFIG=${K8SFS_CONF_DIR}/admin.kubeconfig
    export APISERVER_KEY_LOCATION=${K8SFS_CONF_DIR}/ssl/admin-key.pem
    export APISERVER_CERT_LOCATION=${K8SFS_CONF_DIR}/ssl/admin.pem

    virtual-kubelet \
      --disable-taint \
      --nodename worker \
      --provider mock \
      --provider-config ${K8SFS_CONF_DIR}/mock-config.json \
      &> ${K8SFS_LOG_DIR}/virtual-kubelet.log &
fi

# Done
sleep infinity
