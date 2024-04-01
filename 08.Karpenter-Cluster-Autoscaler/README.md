# Objectives

- Installation and Configuration of Karpenter Cluster Autoscaling


# Karpenter Installation, Configuration

- Prepare the Karpenter environment
  - This installs the Karpenter Controller in the Amazon EKS cluster
  - Terraform reference: https://github.com/aws-samples/eks-workshop-v2/tree/stable/manifests/modules/autoscaling/compute/karpenter/.workshop/terraform

```bash
prepare-environment autoscaling/compute/karpenter
```

- Karpenter runs as a deployment with one pod in the cluster. Let's confirm:

```bash
kubectl get deployment -n karpenter
```

- Update EKS IAM mappings to allow Karpenter nodes join the cluster
  - Ref: https://eksctl.io/usage/iam-identity-mappings/

```bash
eksctl create iamidentitymapping --cluster $EKS_CLUSTER_NAME \
    --region $AWS_REGION --arn $KARP_ARN \
    --group system:bootstrappers --group system:nodes \
    --username system:node:{{EC2PrivateDNSName}}
```

- Create two required CRDs, a **NodePool** and a **EC2NodeClass** 
- These will handle the cluster's scaling needs within defined constraints
- NOTE: For my own AWS account constraints, I changed workshop setting
  - from values: [`c5.large`, `m5.large`, `r5.large`, `m5.xlarge`]
  - to values: [`t3.medium`, `t3.small`, `m5.large`]

```bash
cat ~/environment/eks-workshop/modules/autoscaling/compute/karpenter/nodepool/nodepool.yaml
```

- Apply the NodePool and EC2NodeClass with the following command

```bash
kubectl kustomize ~/environment/eks-workshop/modules/autoscaling/compute/karpenter/nodepool \
  | envsubst | kubectl apply -f-
```

- Watch the Karpenter activity logs

```bash
kubectl logs -l app.kubernetes.io/instance=karpenter -n karpenter | jq
```

- Automatic Node Provisioning
  - Ref: https://www.eksworkshop.com/docs/autoscaling/compute/karpenter/node-provisioning
- Note the initial state of no nodes yet managed by Karpenter

```bash
kubectl get node -l type=karpenter
```

- Create a Deployment with a simple pause container image bit 0 replicas
- Pause containers consume no real resources and starts quickly
  - Ref: https://www.ianlewis.org/en/almighty-pause-container
- NOTE:
  - (1) The `nodeSelector` is set to `type: karpenter` which makes **Karpenter NodePool** schedule pods on nodes with that label
  - (2) Each pod requests 1Gi memory

```bash
cat ~/environment/eks-workshop/modules/autoscaling/compute/karpenter/scale/deployment.yaml
```

- Create the deployment

```bash
kubectl apply -k \
  ~/environment/eks-workshop/modules/autoscaling/compute/karpenter/scale
```

- Force scale this deployment to see Karpenter in action, making optimized decisions. 
- 5 replicas will end up making total of 5Gi of memory (1Gi per pod x 5)
- We'll find out next which instance would Karpenter choose based on the instance types mentioned in the config above and it's optimization logic

```bash
kubectl scale -n other deployment/inflate --replicas 5
```

- Monitor rollout status

```bash
kubectl rollout status -n other deployment/inflate --timeout=180s
```

- Check, which instance type and the purchase option Karpenter chose

```bash
kubectl logs -l app.kubernetes.io/instance=karpenter -n karpenter \
  | grep 'launched nodeclaim' | jq '.'
```

- EC2 instance with 8GB of memory would be sufficient to meet 5Gi memory.
- Karpenter should prioritize the lowest price on-demand instance type 
- A `m5.large` fits the bill.
- NOTE: Karpenter will choose a different instance if the lowest cost option cannot be met due to unavailability and other reasons.
- Query to see instance type, purchase option, availability zone etc.

```bash
kubectl get node -l type=karpenter \
    -o jsonpath='{.items[0].metadata.labels}' | jq '.'
```

# Karpenter Handling Node Disruption

- Simulate the Karpenter controller to automatically detect disruptable nodes, expire, and replace them with new nodes based on the configuration done in the previous section.
- Optimizes the nodes in the cluster when nodes are underutilized due to low-resource demanding workloads running on them.
- To simulate automatic consolidation trigger, when disruption is set to `consolidationPolicy: WhenUnderutilized:`
  - 1. Scale the inflate workload from 5 to 12 replicas.
    - This triggers Karpenter to provision additional capacity
  - 2. Then scale down the workload to 5 replicas
  - 3. Watch Karpenter perform consolidation
- Scale the inflate deployment workload again to consume more resources

```bash
kubectl scale -n other deployment/inflate --replicas 12
kubectl rollout status -n other deployment/inflate --timeout=180s
```

- Expect Karpenter to request and schedule nodes to accomodate higher memory

```bash
kubectl get nodes -l type=karpenter --label-columns node.kubernetes.io/instance-type
```

- Scale the number of replicas back down to 5

```bash
kubectl scale -n other deployment/inflate --replicas 5
```

- Watch Karpenter activity in the logs to see its actions in response to scaling in the deployment. 
- The output will show Karpenter identifying specific nodes to cordon, drain and then terminate nodes

```bash
kubectl logs -l app.kubernetes.io/instance=karpenter -n karpenter \
  | grep 'consolidation delete' | jq '.'
```

- Watch number of nodes post consolidation

```bash
kubectl get nodes -l type=karpenter
```

- Force Karpenter to further consolidate by reducing resource consumption

```bash
kubectl scale -n other deployment/inflate --replicas 1
```

- Check the Karpenter logs by streaming it with `-f` and see what actions the controller took in response:
  - Expect to see Karpenter consolidating by replacing the `m5.large` node with a cheaper instance type defined in the Provisioner (possible `t3` type)

```bash
kubectl logs -l app.kubernetes.io/instance=karpenter -n karpenter -f | jq '.'
```

- Since the total memory request with 1 replica is much lower, 1Gi, Karpenter did find another efficient node to run it on a cheaper instance 
- Confirm the new instance (it turned out to be `t3.small`)

```bash
kubectl get nodes -l type=karpenter -o jsonpath="{range .items[*]}{.metadata.labels.node\.kubernetes\.io/instance-type}{'\n'}{end}"
```

- I confirmed the following result after backing down the replica count to 5, showing 1 out 2 `m5.large` deemed not needed and deleted.
- Then after reducing to 1 replica, I got even cheaper than `t3.medium`, a `t3.small` node as the final consolidation process.
- Also to demonstrate disruption due to expiration, I changed the manifest to a 5-minute expiry with `expireAfter: 5m` directive in the Karpenter configuration manifest and captured the following log. 
- Again predictable behavior by Karpenter. 
- It replaced the old `t3.small` with a new one.
- When scale-out and scale-in of the cluster nodes take place, Karpenter evaluates all available on-demand instance choices and makes the most resource-wise optimal and cost-effective pick.
- We also saw the Karpenter disruption process honoring the node expiration limit specified in the Karpenter configuration manifest, as well as, the consolidation process where underutilized nodes were replaced by resource-efficient and cheaper versions of the nodes from the node pool.




# Resources

- [Karpenter Documentation](https://karpenter.sh/docs/)
- [Github: karpenter-provider-aws](https://github.com/aws/karpenter-provider-aws)
- [Karpenter Best Practices](https://aws.github.io/aws-eks-best-practices/karpenter/)