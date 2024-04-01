# Development IDE (Cloud9)

- In the AWS Shell cope the following sample  of codes

```bash
# Fire the Cloud9 IDE creation cloudformation
wget -q https://raw.githubusercontent.com/aws-samples/eks-workshop-v2/stable/lab/cfn/eks-workshop-ide-cfn.yaml -O eks-workshop-ide-cfn.yaml
aws cloudformation deploy --stack-name eks-workshop \
    --template-file ./eks-workshop-ide-cfn.yaml \
    --parameter-overrides RepositoryRef=stable \
    --capabilities CAPABILITY_NAMED_IAM
```

- Open the Cloud9 IDE, from console or with URL below

```bash
aws cloudformation describe-stacks --stack-name eks-workshop \
    --query 'Stacks[0].Outputs[?OutputKey==`Cloud9Url`].OutputValue' \
    --output text
```

- Finally open the Cloud9 IDE and test the terminal is ready for next steps

```bash
aws sts get-caller-identity
```

# Building Cluster

- Set environemnt variable for REGION.

```bash
export AWS_REGION=eu-west-2
```

- Create/Apply the file `build_cluster.sh`


# Testing Cluster

```bash
# Start by checking the nodes
kubectl get nodes -o wide

# Check if there are any pods running (none expected in default namespace)
kubectl get pods

# Check pods running across all namespaces
kubectl get pods -A

# Glean a little more information about the nodes (e.g. instance types)
kubectl get nodes --show-labels
```

# Resource Cleanup

```bash
# On Cloud9 terminal
# Delete the sample application and any left-over lab infrastructure is removed
delete-environment

# On Cloud9 terminal
# Delete cluster using eksctl
# NOTE: If not deployed any application or built any cluster resources yet
#       just deleting the cluster is sufficient
eksctl delete cluster $EKS_CLUSTER_NAME --wait

# On CloudShell terminal
# Delete the cloudFormation stack 
aws cloudformation delete-stack --stack-name eks-workshop-v1
```