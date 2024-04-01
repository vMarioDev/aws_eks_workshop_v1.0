# Objectives

- Change Amazon VPC CNI IPv4 prefix mode to assign `/28` prefix lists to get 16 additional IP addresses per prefix.
- In this Prefix Assignment Mode, we can configure Amazon VPC CNI (version 1.9.0 or above) to assign `/28` blocks (16 IP addresses) per prefix.


# Configure Amazon VPC CNI

- Prepare your environment for prefix setup and testing

```bash
prepare-environment networking/prefix
```

- Check and make sure VPC CNI is installed and running

```bash
kubectl get pods --selector=k8s-app=aws-node -n kube-system
```

- Confirm the CNI version. CNI version 1.9.0 or later suppots Prefix Mode

```bash
kubectl describe daemonset aws-node --namespace kube-system | \
  grep Image | cut -d "/" -f 2
```

- Next check if the VPC CNI is configured with Prefix Mode
  - The `ENABLE_PREFIX_DELEGATION` should be set to `true`

```bash
kubectl get ds aws-node -o yaml -n kube-system | \
  yq '.spec.template.spec.containers[].env' | grep -C1 ENABLE_PREFIX_DELEGATION
```

- Prefix Mode is enabled
- Describe the prefixes currently assigned to the Node ENIs
- Expect to see 2 for each node

```bash
aws ec2 describe-instances --filters "Name=tag-key,Values=eks:cluster-name" \
  "Name=tag-value,Values=${EKS_CLUSTER_NAME}" \
  --query 'Reservations[*].Instances[].{InstanceId: InstanceId, Prefixes: NetworkInterfaces[].Ipv4Prefixes[]}'
```

# Consume Additional Prefixes

- To demonstrate VPC CNI behavior of using additional prefixes:
  - Deploy pause pods to utilize more IP addresses than are currently assigned
  - Increase the pods counts to a large number
- Review the manifest to do so

```bash
cat ~/environment/eks-workshop/modules/networking/prefix/deployment-pause.yaml
```

- Apply manifest
- Expect this to spin up 150 pods

```bash
kubectl apply -k ~/environment/eks-workshop/modules/networking/prefix
kubectl wait --for=condition=available \
  --timeout=60s deployment/pause-pods-prefix -n other
```

- Wait is over. Check the pause pods are all running

```bash
kubectl get deployment -n other
```

- Once the pods are up and running successfully
- Check to make sure additional prefixes have been added to the worker nodes
- Expect to see 5 or so prefixes 

```bash
aws ec2 describe-instances \
  --filters "Name=tag-key,Values=eks:cluster-name" "Name=tag-value,Values=${EKS_CLUSTER_NAME}" \
  --query 'Reservations[*].Instances[].{InstanceId: InstanceId, Prefixes: NetworkInterfaces[].Ipv4Prefixes[]}'
```


# Resources

- [Prefix Delegation](https://www.eksworkshop.com/docs/networking/vpc-cni/prefix/)
- [Increase the amount of available IP addresses for your Amazon EC2 nodes](https://docs.aws.amazon.com/eks/latest/userguide/cni-increase-ip-addresses.html)
- [Assign prefixes to Amazon EC2 network interfaces](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-prefix-eni.html)
- [Prefix Mode for Linux](https://aws.github.io/aws-eks-best-practices/networking/prefix-mode/index_linux/)
- [Amazon VPC CNI plugin increases pods per node limits](https://aws.amazon.com/blogs/containers/amazon-vpc-cni-increases-pods-per-node-limits/)
