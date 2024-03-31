export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --output text --query 'Account')
export EKS_CLUSTER_NAME=eks-workshop-v1
export K8S_VERSION=1.27
export NG_DESIRED_CAPACITY=2
export EKS_DEFAULT_MNG_MIN=2
export EKS_DEFAULT_MNG_MAX=3
export EKS_DEFAULT_MNG_DESIRED=3
export EKS_DEFAULT_MNG_NAME=default
export INSTANCE_TYPE=t3.medium

# Test env vars
echo "EKS_CLUSTER_NAME : [$EKS_CLUSTER_NAME]"
echo "AWS_REGION : [$AWS_REGION]"
echo "K8S_VERSION : [$K8S_VERSION]"
echo "NG_DESIRED_CAPACITY : [$NG_DESIRED_CAPACITY]"
echo "EKS_DEFAULT_MNG_MIN : [$EKS_DEFAULT_MNG_MIN]"
echo "EKS_DEFAULT_MNG_MAX : [$EKS_DEFAULT_MNG_MAX]"
echo "INSTANCE_TYPE : [$INSTANCE_TYPE]"

# Create the cluster YAML file in /tmp folder
# Good idea for have env vars for desiredCapacity, minSize, maxSize, instanceType
cat <<EOF | tee /tmp/eksctl-cluster.yaml
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig

availabilityZones:
- ${AWS_REGION}a
- ${AWS_REGION}b
- ${AWS_REGION}c

metadata:
  name: ${EKS_CLUSTER_NAME}
  region: ${AWS_REGION}
  version: '${K8S_VERSION}'
  tags:
    karpenter.sh/discovery: ${EKS_CLUSTER_NAME}
    created-by: eks-workshop-v1
    env: ${EKS_CLUSTER_NAME}

iam:
  withOIDC: true

vpc:
  cidr: 10.42.0.0/16
  clusterEndpoints:
    privateAccess: true
    publicAccess: true

addons:
- name: vpc-cni
  version: 1.14.1
  configurationValues:  "{\"env\":{\"ENABLE_PREFIX_DELEGATION\":\"true\", \"ENABLE_POD_ENI\":\"true\", \"POD_SECURITY_GROUP_ENFORCING_MODE\":\"standard\"},\"enableNetworkPolicy\": \"true\"}"
  resolveConflicts: overwrite

managedNodeGroups:
- name: default
  desiredCapacity: ${NG_DESIRED_CAPACITY}
  minSize: ${EKS_DEFAULT_MNG_MIN}
  maxSize: ${EKS_DEFAULT_MNG_MAX}
  instanceType: ${INSTANCE_TYPE}
  privateNetworking: true
  releaseVersion: 1.27.3-20230816
  updateConfig:
    maxUnavailablePercentage: 50
  labels:
    workshop-default: 'yes'
EOF

# Fire cluster creation command
eksctl create cluster -f /tmp/eksctl-cluster.yaml