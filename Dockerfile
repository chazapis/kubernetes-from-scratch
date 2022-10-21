FROM golang:1.18.7 AS builder

WORKDIR /go/src

RUN git clone https://github.com/virtual-kubelet/virtual-kubelet.git && \
    (cd virtual-kubelet && git checkout v1.6.0 && make build)

RUN git clone https://github.com/chazapis/random-scheduler.git && \
    (cd random-scheduler && go build)

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

ARG ETCD_VERSION=v3.4.19
RUN curl -LO https://github.com/etcd-io/etcd/releases/download/${ETCD_VERSION}/etcd-${ETCD_VERSION}-linux-${ARCH}.tar.gz  && \
    tar -zxvf etcd-${ETCD_VERSION}-linux-${ARCH}.tar.gz && \
    cp etcd-${ETCD_VERSION}-linux-${ARCH}/etcd /usr/local/bin/ && \
    cp etcd-${ETCD_VERSION}-linux-${ARCH}/etcdctl /usr/local/bin/ && \
    rm -rf etcd-${ETCD_VERSION}-linux-${ARCH} etcd-${ETCD_VERSION}-linux-${ARCH}.tar.gz

ARG KUBERNETES_VERSION=v1.22.12
RUN curl -LO https://dl.k8s.io/${KUBERNETES_VERSION}/kubernetes-server-linux-${ARCH}.tar.gz && \
    tar -zxvf kubernetes-server-linux-${ARCH}.tar.gz && \
    cp kubernetes/server/bin/kube-apiserver /usr/local/bin/ && \
    cp kubernetes/server/bin/kube-controller-manager /usr/local/bin/ && \
    cp kubernetes/server/bin/kubectl /usr/local/bin/ && \
    rm -rf kubernetes kubernetes-server-linux-${ARCH}.tar.gz

COPY --from=builder /go/src/virtual-kubelet/bin/virtual-kubelet /usr/local/bin/
COPY --from=builder /go/src/random-scheduler/random-scheduler /usr/local/bin/

COPY start.sh /root/
COPY cfssl /root/cfssl/

ENV HPK_BUILTIN_SCHEDULER=1
ENV HPK_BUILTIN_KUBELET=1

CMD ./start.sh
