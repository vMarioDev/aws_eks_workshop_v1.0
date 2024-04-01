# Objectives

- Applying Security Groups to Microservices Pods for Amazon RDS Access


# Implementation

- The process is completed in 3 steps
  - Preparing the cluster environment to deploy the microservices application components, create Amazon RDS instance, and the Security Group to allow access to RDS instance.
  - Migrate the microservices application pods to talk to the managed Amazon RDS service, creating the pod to an external AWS service connection controlled by the Security Groups.
  - Inspecting the pod object to see how the annotations look to understand how the dots are connected to make Security Groups for Pods work.
  - Prepare the environment for this section as usual
  - This makes the following changes to the cluster environment
    - 1. Create an Amazon Relational Database Service instance
    - 2. Create an Amazon EC2 security group to allow access to the RDS instance
      - Terraform ref: https://github.com/aws-samples/eks-workshop-v2/tree/stable/manifests/modules/networking/securitygroups-for-pods/.workshop/terraform

```bash
prepare-environment networking/securitygroups-for-pods
```

- The `catalog` component out of the box, by architecture, uses a MySQL database as the storage backend running on a pod

```bash
kubectl -n catalog get pod 
```

- In the case above, the Pod `catalog-mysql-0` is a MySQL Pod. 
- Verify the `catalog` application is using this by inspecting its environment

```bash
kubectl -n catalog exec deployment/catalog -- env \
  | grep DB_ENDPOINT
```

## Amazon RDS

- NEXT STEP: Migrate application to use the fully managed Amazon RDS 
- An RDS database has been created in the AWS account already
- Retrieve the endpoint and password to be used later

```bash
export CATALOG_RDS_ENDPOINT_QUERY=$(aws rds describe-db-instances --db-instance-identifier $EKS_CLUSTER_NAME-catalog --query 'DBInstances[0].Endpoint')

export CATALOG_RDS_ENDPOINT=$(echo $CATALOG_RDS_ENDPOINT_QUERY | jq -r '.Address+":"+(.Port|tostring)')

echo $CATALOG_RDS_ENDPOINT

export CATALOG_RDS_PASSWORD=$(aws ssm get-parameter --name $EKS_CLUSTER_NAME-catalog-db --region $AWS_REGION --query "Parameter.Value" --output text --with-decryption)
```

- Re-configure the `catalog` service to use an **Amazon RDS dabase**
- The microservice application loads most of its configuration from a `ConfigMap` 
- Inspect the ConfigMap content

```bash
kubectl -n catalog get -o yaml cm catalog
```

- The following kustomization code overwrites the `ConfigMap`.
- It injects the MySQL endpoint, obtained from the env `var CATALOG_RDS_ENDPOINT`.

```bash
cat ~/environment/eks-workshop/modules/networking/securitygroups-for-pods/rds/kustomization.yaml
```

- Apply the change to use the the RDS database

```bash
kubectl kustomize ~/environment/eks-workshop/modules/networking/securitygroups-for-pods/rds \
  | envsubst | kubectl apply -f-
```

- Confirm the `ConfigMap` now the new values

```bash
kubectl get -n catalog cm catalog -o yaml
```

- Recycle the `catalog` Pods to pick up the new `ConfigMap` contents
- Expect error during rollout. 
- `Catalog` Pods should fail to restart in time

```bash
kubectl delete pod -n catalog -l app.kubernetes.io/component=service
kubectl rollout status -n catalog deployment/catalog --timeout 30s
```

- Check pod logs to see what's wrong

```bash
kubectl -n catalog logs deployment/catalog
```

- Pod is unable to connect to the RDS database
- Security Group is the suspect
- Check the EC2 Security Group applied to the RDS database using AWS CLI 
  - Or view the security group of the RDS instance through the AWS EC2 console

```bash
aws ec2 describe-security-groups \
    --filters Name=vpc-id,Values=$VPC_ID Name=tag:Name,Values=$EKS_CLUSTER_NAME-catalog-rds | jq '.'
```

- This security group only allows traffic to access the RDS database on port 3306 if it comes from a source which has a specific security group

## Applying Security Group

- In order for `catalog` Pod to successfully connect to the RDS instance it needs the correct security group.
- Although the above security group could be applied to the EKS worker nodes themselves, it would result in any workload in the cluster having network access to the RDS instance.
- Best approach is to apply Security Groups for Pods to specifically allow `catalog` Pods access to the RDS instance.
- A security group with allowed access to the RDS database exists 
- It was done as part of the initial setup

```bash
export CATALOG_SG_ID=$(aws ec2 describe-security-groups \
    --filters Name=vpc-id,Values=$VPC_ID Name=group-name,Values=$EKS_CLUSTER_NAME-catalog \
    --query "SecurityGroups[0].GroupId" --output text)
aws ec2 describe-security-groups \
  --group-ids $CATALOG_SG_ID | jq '.'
```

- This security group:
  - 1. Allows inbound traffic for the HTTP API served by the Pod on port 8080
  - 2. Allows all egress traffic
  - 3. Allows access the RDS database
- In order for the Pod to use this SG:
  - Use the SecurityGroupPolicy CRD to tell EKS which security group is to be mapped to a specific set of Pods. 
- Review configuration

```bash
cat ~/environment/eks-workshop/modules/networking/securitygroups-for-pods/sg/policy.yaml
```

- Apply configuration to the cluster and recycle the catalog Pods like before

```bash
kubectl kustomize ~/environment/eks-workshop/modules/networking/securitygroups-for-pods/sg \
  | envsubst | kubectl apply -f-
kubectl delete pod -n catalog -l app.kubernetes.io/component=service
kubectl rollout status -n catalog deployment/catalog --timeout 30s
```

- `Catalog` Pod restarts and the rollout is successful
- Check the logs to confirm its connecting to the RDS database

```bash
kubectl -n catalog logs deployment/catalog | grep Connect
```

## Inspecting The Pod

- The `Catalog` Pod is running and successfully connecting to the RDS database
- Examine the pod object's manifest to see what signals are present
- First check the annotations of the Pod

```bash
kubectl get pod -n catalog -l app.kubernetes.io/component=service -o yaml \
  | yq '.items[0].metadata.annotations'
```

- The `vpc.amazonaws.com/pod-eni` annotation shows metadata of the branch ENI that's been used for this Pod, its private IP address, etc.
- Check Kubernetes events to see the VPC resource controller taking action in response to the configuration added

```bash
kubectl get events -n catalog | grep SecurityGroupRequested
```

- Finally, check the ENIs managed by the VPC resource controller in the EC2 ENI console.
- This shows information about the branch ENI including the security group assigned.







# Resources

- [Introducing security groups for pods](https://aws.amazon.com/blogs/containers/introducing-security-groups-for-pods/)
- [AWS Workshop: Security Groups for Pods](https://www.eksworkshop.com/docs/networking/vpc-cni/security-groups-for-pods/)
- [AWS: Security groups for Pods](https://docs.aws.amazon.com/eks/latest/userguide/security-groups-for-pods.html)
- [Security Groups Per Pod](https://aws.github.io/aws-eks-best-practices/networking/sgpp/)
- [EKS Best Practices Guides](https://aws.github.io/aws-eks-best-practices/)
- [amazon-vpc-resource-controller-k8s](https://github.com/aws/amazon-vpc-resource-controller-k8s)
- [vpcresources.k8s.aws_securitygrouppolicies.yaml](https://github.com/aws/amazon-vpc-resource-controller-k8s/blob/master/config/crd/bases/vpcresources.k8s.aws_securitygrouppolicies.yaml)
