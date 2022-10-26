# Kubernetes from scratch

The purpose of this repository is to boostrap a very basic Kubernetes environment for experimenting with custom Kubernetes components, especially [Virtual Kubelet](https://github.com/virtual-kubelet/virtual-kubelet) implementations. Pre-built container images are [available](https://hub.docker.com/r/chazapis/kubernetes-from-scratch) (note the architecture).

Example usage:
```bash
docker run -d --rm -p 6443:6443 --name k8sfs chazapis/kubernetes-from-scratch:<tag>
docker cp k8sfs:/root/.kube/config kubeconfig
export KUBECONFIG=$PWD/kubeconfig
kubectl version
```

Use the following environment variables to customize:

| Variable                  | Description                                | Default |
|---------------------------|--------------------------------------------|---------|
| `K8SFS_BUILTIN_SCHEDULER` | Start the built-in pass-through scheduler. | `1`     |
| `K8SFS_BUILTIN_KUBELET`   | Start the built-in mock kubelet.           | `1`     |

To build and push for multiple architectures:
```bash
docker buildx build --platform linux/amd64,linux/arm64 --push -t chazapis/kubernetes-from-scratch:<tag> .
```

Based on the excellent [Kubernetes The Hard Way](https://github.com/kelseyhightower/kubernetes-the-hard-way) and [Kubernetes Deployment From Scratch - The Ultimate Guide](https://www.ulam.io/blog/kubernetes-scratch).
