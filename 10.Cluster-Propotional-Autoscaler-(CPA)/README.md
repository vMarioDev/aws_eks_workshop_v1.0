# Objectives

- Use the CoreDNS deployment resource as the target of the CPA resource and see its scaling action by increasing the number of nodes in our EKS cluster.





# Deploy Cluster Proportional Autoscaler

- Prepare the CPA environment once the cluster is ready

```bash
prepare-environment autoscaling/workloads/cpa
```

- Review the Deployment manifest in the Kustomize manifest folder
- This holds the glue of connecting the target CoreDNS deployment with CPA

```bash
cat ~/environment/eks-workshop/modules/autoscaling/workloads/cpa/deployment.yaml
```

- Apply the Kustomize manifests to create the resources
- The Deployment is created in the kube-system namespace

```bash
kubectl apply -k ~/environment/eks-workshop/modules/autoscaling/workloads/cpa
```

- Check the deployment object running

```bash
kubectl get -f ~/environment/eks-workshop/modules/autoscaling/workloads/cpa/deployment.yaml
```

- CPA creates a `ConfigMap`
- The autoscaling parameters are tuned in the CM configuration
  - Ref: https://kubernetes.io/docs/tasks/administer-cluster/dns-horizontal-autoscaling/#tuning-autoscaling-parameters

```bash
kubectl describe configmap dns-autoscaler -n kube-system
```

- Autoscaling of **CoreDNS** depends on the number of schedulable nodes and cores in the cluster
- CPA resizes the number of CoreDNS replicas
- Check the number of node in the cluster first

```bash
kubectl get nodes
```

- The `ConfigMap` configurations shows min of 2 replicas and max of 6
- CPA accordingly scales **CoreDNS** to 2 replicas
- Confirm **CoreDNS** replicas

```bash
kubectl get po -n kube-system -l k8s-app=kube-dns
```

- To test CPA scale-up, increase the nubmer of cluster node to 5

```bash
aws eks update-nodegroup-config --cluster-name $EKS_CLUSTER_NAME \
  --nodegroup-name $EKS_DEFAULT_MNG_NAME --scaling-config desiredSize=$(($EKS_DEFAULT_MNG_DESIRED+2))

aws eks wait nodegroup-active --cluster-name $EKS_CLUSTER_NAME \
  --nodegroup-name $EKS_DEFAULT_MNG_NAME

kubectl wait --for=condition=Ready nodes --all --timeout=120s
```

- Confirm cluster compute nodes are now 5 and all in ready state

```bash
kubectl get nodes
```

- Check to make sure the number of CoreDNS Pods has increased

```bash
kubectl get po -n kube-system -l k8s-app=kube-dns
```

- Finally, check the CPA logs to see how it responded to the change in the number of nodes in the cluster

```bash
kubectl logs deploy/dns-autoscaler -n other
```

- You can use CPA to meet the following use cases:
  - Over-provisioning
  - Autoscale core platform services
- An autoscaler alternative that provides a simple and easy mechanism to scale out workloads if you don’t want to install **Metrics Server** or similar solutions like **Prometheus Adapter**.












# Resources

- [AWS Workshop: Cluster Proportional Autoscaler](https://www.eksworkshop.com/docs/autoscaling/workloads/cluster-proportional-autoscaler/)
- [Autoscale the DNS Service in a Cluster](https://kubernetes.io/docs/tasks/administer-cluster/dns-horizontal-autoscaling/)
- [Github: Horizontal cluster-proportional-autoscaler container](https://github.com/kubernetes-sigs/cluster-proportional-autoscaler/blob/master/README.md)