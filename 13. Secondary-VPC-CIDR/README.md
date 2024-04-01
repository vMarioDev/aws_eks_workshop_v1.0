# Objectives

- Solve the IP address exhaustion issue by assigning a secondary IPv4 CIDR block to the VPC with the support of Kubernetes custom resource `ENIConfig`.
- The solution involves the following steps:
  - Attach a secondary CIDR range to the VPC
  - Enable **Amazon VPC CNI Custom Networking** mode for **VPC CNI**
  - Create `ENIConfig` custom resource for each subnet with the secondary CIDR range.
  - Create a cluster node in the new subnet, force pods to run in the new node using `nodeSelector` directive in the deployment, and see that they are assigned IP addresses from the secondary CIDR block.

# Implementation

- Prepare the environment for Custom Networking 
- This makes the following changes in the Amazon EKS Cluster
  - 1. Attaches a secondary CIDR range to the VPC
  - 2. Creates three additional subnets from the secondary CIDR range
  - Terraform Ref: https://github.com/aws-samples/eks-workshop-v2/tree/stable/manifests/modules/networking/custom-networking/.workshop/terraform

```bash
prepare-environment networking/custom-networking
```

## VPC Architecture Review

- Start by inspecting the VPC of the EKS Cluster
- Describe the VPC using AWS CLI
- Expect to see two CIDR ranges associated with the VPC
  - 10.42.0.0/16 range, the "primary" CIDR
  - 100.64.0.0/16 range, the "secondary" CIDR
- NOTE: You can also view this in the AWS VPC Service console

```bash
aws ec2 describe-vpcs --vpc-ids $VPC_ID
```

- Show all the subnets present in the VPC
- Expect to see a total of 9 subnets

```bash
aws ec2 describe-subnets --filters "Name=tag:created-by,Values=eks-workshop-v2" \
  --query "Subnets[*].CidrBlock"
```

- At this time, all pods are leveraging the private subnets IP pool `10.42.96.0/19`, `10.42.128.0/19` and `10.42.160.0/19`
- As part of this lab, we'll move a few to consume the secondary IP addresses from the 100.64 subnets.

## Configure Amazon VPC CNI

- Configure the Amazon VPC CNI to use the secondary CIDR range `100.64.0.0/16`
- Check both one more time like we saw above, just the CIDRs here

```bash
aws ec2 describe-vpcs --vpc-ids $VPC_ID | \
    jq '.Vpcs[0].CidrBlockAssociationSet'
```

- In the new CIDR range we have created 3 new subnets in the VPC
- List all of them here as FYI

```bash
echo "The secondary subnet in AZ $SUBNET_AZ_1 is $SECONDARY_SUBNET_1"
echo "The secondary subnet in AZ $SUBNET_AZ_2 is $SECONDARY_SUBNET_2"
echo "The secondary subnet in AZ $SUBNET_AZ_3 is $SECONDARY_SUBNET_3"
```

- Enable VPC CNI with Custom Networking operation mode
- The `AWS_VPC_K8S_CNI_CUSTOM_NETWORK_CFG` environment variable must be set to `true` in the `aws-node` DaemonSet running on each node

```bash
kubectl set env daemonset aws-node -n kube-system AWS_VPC_K8S_CNI_CUSTOM_NETWORK_CFG=true
```

## Create Custom Resource: ENIConfig

- Create an ENIConfig custom resource for each new subnet
- New pods will be hosted in cluster node running in this subnet
- Review the manifest

```bash
cat ~/environment/eks-workshop/modules/networking/custom-networking/provision/eniconfigs.yaml
```

- Apply manifest

```bash
kubectl kustomize ~/environment/eks-workshop/modules/networking/custom-networking/provision \
  | envsubst | kubectl apply -f-
```

- Confirm that the ENIConfig objects were created

```bash
kubectl get ENIConfigs
```

- Finally update the `aws-node` DaemonSet to automatically apply the `ENIConfig` for an Availability Zone to any new Amazon EC2 nodes created in the EKS cluster.

```bash
kubectl set env daemonset aws-node -n kube-system ENI_CONFIG_LABEL_DEF=topology.kubernetes.io/zone
```

## Provision A New Node Group

- Create another EKS managed node group with 1 node only

```bash
aws eks create-nodegroup --region $AWS_REGION \
  --cluster-name $EKS_CLUSTER_NAME \
  --nodegroup-name custom-networking \
  --instance-types t3.medium --node-role $CUSTOM_NETWORKING_NODE_ROLE \
  --subnets $PRIMARY_SUBNET_1 $PRIMARY_SUBNET_2 $PRIMARY_SUBNET_3 \
  --labels type=customnetworking \
  --scaling-config minSize=1,maxSize=1,desiredSize=1
```

- Node group creation takes several minutes.
- Wait for the node group creation to complete

```bash
aws eks wait nodegroup-active --cluster-name $EKS_CLUSTER_NAME --nodegroup-name custom-networking
```

- Node group creation finished
- Verify the new nodes registered in the EKS cluster
- Expect to see 1 new node provisioned with label of the new node group

```bash
kubectl get nodes -L eks.amazonaws.com/nodegroup
```

## Redeploy Workload

- In order to test the custom networking working
- We need to deploy a deployment's pods on this node
- Update the `Checkout` deployment to run the pods in the new node
- The `nodeSelector` with the new node is used in the `Checkout` deployment
- Review manifest

```bash
cat ~/environment/eks-workshop/modules/networking/custom-networking/sampleapp/checkout.yaml
```

- Apply the modified Checkout deployment in the cluster

```bash
kubectl apply -k ~/environment/eks-workshop/modules/networking/custom-networking/sampleapp
kubectl rollout status deployment/checkout -n checkout --timeout 180s
```

- Review the microservices deployed in the `checkout` namespace.

```bash
kubectl get pods -n checkout -o wide
```

- Here we see that the checkout pod is assigned an IP address from the `100.64.0.0` secondary CIDR block that was added to the VPC.
- Pods that have not yet been redeployed are still assigned addresses from the `10.42.0.0` primary CIDR block as expected 
- For example, the `checkout-redis` pod still has an address from primary range.


# Resources

- [Amazon EKS now supports additional VPC CIDR blocks](https://aws.amazon.com/about-aws/whats-new/2018/10/amazon-eks-now-supports-additional-vpc-cidr-blocks/)
- [AWS Workshop: Custom Networking](https://www.eksworkshop.com/docs/networking/vpc-cni/custom-networking/)
- [AWS Custom networking for pods](https://docs.aws.amazon.com/eks/latest/userguide/cni-custom-network.html)
- [EKS Best Practice: Amazon VPC CNI](https://aws.github.io/aws-eks-best-practices/networking/vpc-cni/)
- [EKS Best Practices](https://aws.github.io/aws-eks-best-practices/)
- [Optimizing IP Address Utilization](https://aws.github.io/aws-eks-best-practices/networking/ip-optimization-strategies/)
- [Addressing IPv4 address exhaustion in Amazon EKS clusters using private NAT gateways](https://aws.amazon.com/blogs/containers/addressing-ipv4-address-exhaustion-in-amazon-eks-clusters-using-private-nat-gateways/)
- [Automating custom networking to solve IPv4 exhaustion in Amazon EKS](https://aws.amazon.com/blogs/containers/automating-custom-networking-to-solve-ipv4-exhaustion-in-amazon-eks/)
- [Optimize IP addresses usage by pods in your Amazon EKS cluster](https://aws.amazon.com/blogs/containers/optimize-ip-addresses-usage-by-pods-in-your-amazon-eks-cluster/)
- [Leveraging CNI custom networking alongside security groups for pods in Amazon EKS][(](https://aws.amazon.com/blogs/containers/leveraging-cni-custom-networking-alongside-security-groups-for-pods-in-amazon-eks/))