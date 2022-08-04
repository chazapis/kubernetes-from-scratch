# Kubernetes from scratch

The purpose of this repository is to boostrap a very basic Kubernetes environment for experimenting with custom implementations of Kubernetes components. Pre-built container images are [available](https://hub.docker.com/r/chazapis/kubernetes-from-scratch) (note the architecture).

Example usage:
```bash
docker run -d --rm -p 6443:6443 --name k8sfs chazapis/kubernetes-from-scratch:20220803
docker cp k8sfs:/root/.kube/config kubeconfig
export KUBECONFIG=$PWD/kubeconfig
kubectl version
```

Based on the excellent [Kubernetes The Hard Way](https://github.com/kelseyhightower/kubernetes-the-hard-way) and [Kubernetes Deployment From Scratch - The Ultimate Guide](https://www.ulam.io/blog/kubernetes-scratch).
