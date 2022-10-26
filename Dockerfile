FROM golang:1.18.7 AS builder

WORKDIR /go/src

RUN git clone https://github.com/chazapis/random-scheduler.git && \
    (cd random-scheduler && go build)

RUN git clone https://github.com/virtual-kubelet/virtual-kubelet.git && \
    (cd virtual-kubelet && git checkout v1.6.0 && make build)

FROM ubuntu:20.04

RUN apt-get update && \
    apt-get install -y curl golang-cfssl && \
    apt-get clean \
    && rm -rf \
        /var/lib/apt/lists/* \
        /tmp/* \
        /var/tmp/* \
        /usr/share/man \
        /usr/share/doc \
        /usr/share/doc-base

WORKDIR /root

ARG ARCH=arm64

ARG ETCD_VERSION=3.4.21
RUN curl -LO https://github.com/etcd-io/etcd/releases/download/v${ETCD_VERSION}/etcd-v${ETCD_VERSION}-linux-${ARCH}.tar.gz  && \
    tar -zxvf etcd-v${ETCD_VERSION}-linux-${ARCH}.tar.gz && \
    cp etcd-v${ETCD_VERSION}-linux-${ARCH}/etcd /usr/local/bin/ && \
    cp etcd-v${ETCD_VERSION}-linux-${ARCH}/etcdctl /usr/local/bin/ && \
    rm -rf etcd-v${ETCD_VERSION}-linux-${ARCH} etcd-v${ETCD_VERSION}-linux-${ARCH}.tar.gz

ARG KUBERNETES_VERSION=1.22.15
RUN curl -LO https://dl.k8s.io/v${KUBERNETES_VERSION}/kubernetes-server-linux-${ARCH}.tar.gz && \
    tar -zxvf kubernetes-server-linux-${ARCH}.tar.gz && \
    cp kubernetes/server/bin/kube-apiserver /usr/local/bin/ && \
    cp kubernetes/server/bin/kube-controller-manager /usr/local/bin/ && \
    cp kubernetes/server/bin/kubectl /usr/local/bin/ && \
    rm -rf kubernetes kubernetes-server-linux-${ARCH}.tar.gz

ARG COREDNS_VERSION=1.8.7
RUN curl -LO https://github.com/coredns/coredns/releases/download/v${COREDNS_VERSION}/coredns_${COREDNS_VERSION}_linux_${ARCH}.tgz && \
    tar -zxvf coredns_${COREDNS_VERSION}_linux_${ARCH}.tgz && \
    cp coredns /usr/local/bin/ && \
    rm -rf coredns coredns_${COREDNS_VERSION}_linux_${ARCH}.tgz

COPY --from=builder /go/src/random-scheduler/random-scheduler /usr/local/bin/
COPY --from=builder /go/src/virtual-kubelet/bin/virtual-kubelet /usr/local/bin/

COPY start.sh /root/
COPY cfssl /root/cfssl/

ENV K8SFS_BUILTIN_SCHEDULER=1
ENV K8SFS_BUILTIN_KUBELET=1

CMD ./start.sh
