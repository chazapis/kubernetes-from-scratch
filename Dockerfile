FROM golang:1.18.7 AS builder

WORKDIR /go/src

COPY services-webhook /go/src/services-webhook
RUN (cd services-webhook && go build)

COPY random-scheduler /go/src/random-scheduler
RUN (cd random-scheduler && go build)

RUN git clone https://github.com/virtual-kubelet/virtual-kubelet.git && \
    (cd virtual-kubelet && git checkout v1.6.0 && make build)

FROM ubuntu:20.04

RUN apt-get update && \
    apt-get install -y iproute2 curl golang-cfssl && \
    apt-get clean \
    && rm -rf \
        /var/lib/apt/lists/* \
        /tmp/* \
        /var/tmp/* \
        /usr/share/man \
        /usr/share/doc \
        /usr/share/doc-base

WORKDIR /root

ARG TARGETARCH

ARG ETCD_VERSION=3.5.5
RUN curl -LO https://github.com/etcd-io/etcd/releases/download/v${ETCD_VERSION}/etcd-v${ETCD_VERSION}-linux-${TARGETARCH}.tar.gz  && \
    tar -zxvf etcd-v${ETCD_VERSION}-linux-${TARGETARCH}.tar.gz && \
    cp etcd-v${ETCD_VERSION}-linux-${TARGETARCH}/etcd /usr/local/bin/ && \
    cp etcd-v${ETCD_VERSION}-linux-${TARGETARCH}/etcdctl /usr/local/bin/ && \
    rm -rf etcd-v${ETCD_VERSION}-linux-${TARGETARCH} etcd-v${ETCD_VERSION}-linux-${TARGETARCH}.tar.gz

ARG KUBERNETES_VERSION=1.24.7
RUN curl -LO https://dl.k8s.io/v${KUBERNETES_VERSION}/kubernetes-server-linux-${TARGETARCH}.tar.gz && \
    tar -zxvf kubernetes-server-linux-${TARGETARCH}.tar.gz && \
    cp kubernetes/server/bin/kube-apiserver /usr/local/bin/ && \
    cp kubernetes/server/bin/kube-controller-manager /usr/local/bin/ && \
    cp kubernetes/server/bin/kubectl /usr/local/bin/ && \
    rm -rf kubernetes kubernetes-server-linux-${TARGETARCH}.tar.gz

ARG COREDNS_VERSION=1.10.0
RUN curl -LO https://github.com/coredns/coredns/releases/download/v${COREDNS_VERSION}/coredns_${COREDNS_VERSION}_linux_${TARGETARCH}.tgz && \
    tar -zxvf coredns_${COREDNS_VERSION}_linux_${TARGETARCH}.tgz && \
    cp coredns /usr/local/bin/ && \
    rm -rf coredns coredns_${COREDNS_VERSION}_linux_${TARGETARCH}.tgz

COPY --from=builder /go/src/services-webhook/services-webhook /usr/local/bin/
COPY --from=builder /go/src/random-scheduler/random-scheduler /usr/local/bin/
COPY --from=builder /go/src/virtual-kubelet/bin/virtual-kubelet /usr/local/bin/

COPY cfssl /var/local/cfssl
COPY start-kubernetes.sh /usr/local/bin/

ENV K8SFS_HEADLESS_SERVICES=1
ENV K8SFS_RANDOM_SCHEDULER=1
ENV K8SFS_MOCK_KUBELET=1

CMD /usr/local/bin/start-kubernetes.sh
