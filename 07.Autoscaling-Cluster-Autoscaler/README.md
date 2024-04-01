# Objectives

- Configure and Test Cluster Autoscaler

# Simple Autoscaling

- Prepare the CA environment
- This installs the application microservices as well as the Kubernetes Cluster Autoscaler in the Amazon EKS cluster

```bash
prepare-environment autoscaling/compute/cluster-autoscaler
```

- The CA component runs as a deployment in the kube-system namespace.
- Confirm it's deployed and running

```bash
kubectl get deployment -n kube-system cluster-autoscaler-aws-cluster-autoscaler
```

- Check the application deployment replicas to begin with 

```bash
kubectl get deployment -A
```

- And number of nodes available

```bash
kubectl get nodes -l workshop-default=yes
```

- To test CA, we'll update all of the application components to increase their replica count to 4, and in turn increase resources consumed available in a cluster triggering more compute nodes to be provisioned
- Review the manifest

```bash
cat ~/environment/eks-workshop/modules/autoscaling/compute/cluster-autoscaler/deployment.yaml
```

- Apply manifest cluster

```bash
kubectl apply -k ~/environment/eks-workshop/modules/autoscaling/compute/cluster-autoscaler
```

- Check the deployments to confirm scale out. 
- Eventuall all should reach 4/4 ready pods

```bash
kubectl get deployment -A
```

- Check the pods as they are come up and trigger the cluster-autoscaler to scale out the EC2 fleet

```bash
kubectl get pods -n orders -o wide --watch
```

- View the `cluster-autoscaler` logs to monitor how the CA works underneath

```bash
kubectl -n kube-system logs \
  -f deployment/cluster-autoscaler-aws-cluster-autoscaler
```

- Confirm cluster nodes have scaled out from the initial 3 counts of node to 6 or so
  - (1) By looking at the EC2 console
  - (2) With `kubectl` command below

```bash
kubectl get nodes -l workshop-default=yes
```

- Scale-out is successfull. Let's try scale-in.
- Scale-in the replicas back to 1 or 2 for each deployment by editing the manifest

```bash
cat ~/environment/eks-workshop/modules/autoscaling/compute/cluster-autoscaler/deployment.yaml
```

- Apply manifest

```bash
kubectl apply -k ~/environment/eks-workshop/modules/autoscaling/compute/cluster-autoscaler
```

- Check the deployments to confirm scale in of replicas
- Also check the pods

```bash
kubectl get deployment -A
kubectl get pods -n orders -o wide --watch
```

- There is a 10 minutes wait time before CAS starts removing nodes
  - Ref: https://github.com/kubernetes/autoscaler/blob/master/cluster-autoscaler/FAQ.md
- Confirm the node count has reduced (as needed for 2 replicas vs. 4)

```bash
kubectl get nodes -l workshop-default=yes
```

# Cluster Over-Provisioning

- Cluster over-provisioning provisions extra nodes ahead of time by creating lower-priority pods as placeholders. 
- When real critical application pods with a higher priority come into existence, the lower priority pods are evicted and replaced. 
- This helps to cut down the extra time needed to provision the nodes while the critical application pods wait as we saw previously.
- Start by creating a global **Default Priority Class** 
- This **default PriorityClass** will be assigned to `pods/deployments` that don’t specify a PriorityClassName.

```bash
cat ~/environment/eks-workshop/modules/autoscaling/compute/overprovisioning/setup/priorityclass-default.yaml
```

- Then create PriorityClass that will be assigned to `pause` pods used for over-provisioning with priority value -1.

```bash
cat ~/environment/eks-workshop/modules/autoscaling/compute/overprovisioning/setup/priorityclass-pause.yaml
```

- Pause pods make sure there are enough nodes that are available based on how much over provisioning is needed for your environment. 
- Note that the `—max-size` parameter in ASG (of EKS node group) limits the CA's ability to increase number of nodes beyond this max.
- Verify it by looking at the ASG console window
- Review the pause pod manifest

```bash
cat ~/environment/eks-workshop/modules/autoscaling/compute/overprovisioning/setup/deployment-pause.yaml
```

- We have a single pause pod requesting 7Gi of memory.
- That's sufficient to consume almost an entire `m5.large` instance. 
- This will result in us always having 2 "spare" worker nodes available.
- NOTE: This EKS cluster creation limted to t2.medium, so I reduced the memory to 2Gi to provision more of these nodes
- Apply the updates to your cluster:

```bash
kubectl apply -k ~/environment/eks-workshop/modules/autoscaling/compute/overprovisioning/setup
kubectl rollout status -n other deployment/pause-pods --timeout 300s
```

- Confirm cluster nodes have scaled out from the initial 3 counts of node to 6 or so
  - (1) By looking at the EC2 console
  - (2) With kubectl command below
- These extra nodes added are not running any workloads except for the pause pods, which will be evicted when real workloads are scheduled.

```bash
kubectl get nodes -l workshop-default=yes
```

- With sufficient nodes, the pause pods should be running

```bash
kubectl get pods -n other
```

- Time to scale up the entire application architecture to 5 replicas 
- Review manifest

```bash
cat ~/environment/eks-workshop/modules/autoscaling/compute/overprovisioning/scale/deployment.yaml
```

- Apply the updated manifest to cluster

```bash
kubectl apply -k ~/environment/eks-workshop/modules/autoscaling/compute/overprovisioning/scale
kubectl wait --for=condition=Ready --timeout=180s pods -l app.kubernetes.io/created-by=eks-workshop -A
```

- Confirm applications pods are all scheduled and running
- If ASG limits max node, even some of these nodes will be in pending state

```bash
kubectl get pods -n orders -o wide --watch
```

- As the high priority application workload pods come up, the pause pod will be evicted to make room for the workload pods. 
- Which means the pause pods will be evicted and be in Pending state
- This process is much quickers since the nodes were already waiting

```bash
kubectl get pod -n other -l run=pause-pods
```




# Resources

- [Cluster Autoscaler](https://github.com/kubernetes/autoscaler/tree/master/cluster-autoscaler#cluster-autoscaler)
- [Frequently Asked Questions](https://github.com/kubernetes/autoscaler/blob/master/cluster-autoscaler/FAQ.md)
- [Autoscaler Deployment](https://github.com/kubernetes/autoscaler/tree/master/cluster-autoscaler#deployment)
- [Cluster Autoscaler on AWS](https://github.com/kubernetes/autoscaler/tree/master/cluster-autoscaler/cloudprovider/aws#cluster-autoscaler-on-aws)
- [AWS Auto Scaling groups](https://docs.aws.amazon.com/autoscaling/ec2/userguide/auto-scaling-groups.html)
- [Managed node groups](https://docs.aws.amazon.com/eks/latest/userguide/managed-node-groups.html)
- [Pod Priority and Preemption](https://kubernetes.io/docs/concepts/scheduling-eviction/pod-priority-preemption/)
- [The Almighty Pause Container](https://www.ianlewis.org/en/almighty-pause-container)
- [AWS Workshop: Cluster Over-Provisioning](https://www.eksworkshop.com/docs/autoscaling/compute/cluster-autoscaler/overprovisioning/how-it-works/)


