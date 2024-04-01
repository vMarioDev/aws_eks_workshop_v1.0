# Objectives

- Complex integration of **Amazon VPC Lattice** in **Amazon EKS Cluster** and performing a Microservice Canary Deployment!
- Implement Advanced Traffic Management and Application Layer Routing.
- Follow all the recommended steps prescribed by VPC Lattice and the components involved.
  - **Install AWS Gateway API Controller**
    - An open-source project and fully supported by Amazon. 
    - The controller integrates **VPC Lattice** with the **Kubernetes Gateway API**. 
    - Once successfully installed in the cluster, the controller watches for the creation of Gateway API resources:
      - **GatewayClass**, **Gateways**, and **Routes** and provisions corresponding Amazon VPC Lattice objects. 
    - This enables users to configure **VPC Lattice Service Networks** using Kubernetes APIs, without needing to write custom code or manage sidecar proxies.
  - **Create Gateway Resources (GatewayClass, Gateway)** 
    - Confirm **VPC Lattice Service Network** is connected with the Gateway object.
  - Create two versions of one of the Application Microservices deployment.
  - Create **HTTPRoute** object and configure **Canary Traffic Routing** by distributing traffic based on different weights assigned to two different services deployed.


# Canary Traffic Routing Implementation

- Prepare the cluster environment for this demonstration
- This makes the following two changes in the EKS Cluster:
  - 1. Create an IAM role for the Gateway API controller to access AWS APIs
  - 2. Install the AWS Load Balancer Controller in the Amazon EKS cluster
- Terraform ref: https://github.com/aws-samples/eks-workshop-v2/tree/stable/manifests/modules/networking/vpc-lattice/.workshop/terraform

```bash
prepare-environment networking/vpc-lattice
```

## AWS Gateway API Controller

- Create a cluster and deploy the AWS Gateway API Controller
- Configure security group to receive traffic from the VPC Lattice network.
- Security Groups are needed to allow all Pods communicate with 
- VPC Lattice managed prefix lists (both IPv4 and IPv6). 

```bash
CLUSTER_SG=$(aws eks describe-cluster --name $EKS_CLUSTER_NAME --output json| jq -r '.cluster.resourcesVpcConfig.clusterSecurityGroupId')

PREFIX_LIST_ID=$(aws ec2 describe-managed-prefix-lists --query "PrefixLists[?PrefixListName=="\'com.amazonaws.$AWS_REGION.vpc-lattice\'"].PrefixListId" | jq -r '.[]')

aws ec2 authorize-security-group-ingress --group-id $CLUSTER_SG --ip-permissions "PrefixListIds=[{PrefixListId=${PREFIX_LIST_ID}}],IpProtocol=-1"

PREFIX_LIST_ID_IPV6=$(aws ec2 describe-managed-prefix-lists --query "PrefixLists[?PrefixListName=="\'com.amazonaws.$AWS_REGION.ipv6.vpc-lattice\'"].PrefixListId" | jq -r '.[]')

aws ec2 authorize-security-group-ingress --group-id $CLUSTER_SG --ip-permissions "PrefixListIds=[{PrefixListId=${PREFIX_LIST_ID_IPV6}}],IpProtocol=-1"
```

- Install the **Controller** and the CRDs (Custom Resource Definitions) required to interact with the Kubernetes Gateway API.

```bash
aws ecr-public get-login-password --region us-east-1 \
  | helm registry login --username AWS --password-stdin public.ecr.aws

helm install gateway-api-controller \
    oci://public.ecr.aws/aws-application-networking-k8s/aws-gateway-controller-chart \
    --version=v1.0.1 \
    --create-namespace \
    --set=aws.region=${AWS_REGION} \
    --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"="$LATTICE_IAM_ROLE" \
    --set=defaultServiceNetwork=${EKS_CLUSTER_NAME} \
    --namespace gateway-api-controller \
    --wait
```

- Confirm that the controller is running successfully as a Deployment

```bash
kubectl get deployment -n gateway-api-controller
```

## AWS VPC Lattice Service Network

- The **Gateway API controller** is configured to create:
  - VPC Lattice Service Network component
  - Associate a Kubernetes cluster VPC automatically.
- Create a **GatewayClass** resource object in the cluster
- This identified VPC Lattice as the **GatewayClass**
- Later Gateway resource object will make reference to the **GatewayClass**

```bash
cat ~/environment/eks-workshop/modules/networking/vpc-lattice/controller/gatewayclass.yaml
```

- Apply manifest and create the GatewayClass

```bash
kubectl apply -f ~/environment/eks-workshop/modules/networking/vpc-lattice/controller/gatewayclass.yaml
```

- Create a Kubernetes Gateway resource associated with VPC Lattice Service Network.

```bash
cat ~/environment/eks-workshop/modules/networking/vpc-lattice/controller/eks-workshop-gw.yaml
```

- Apply manifest and create Gateway

```bash
cat ~/environment/eks-workshop/modules/networking/vpc-lattice/controller/eks-workshop-gw.yaml \
  | envsubst | kubectl apply -f -
```

- Verify Gateway is created

```bash
kubectl get gateway -n checkout
```

- After Gateway creation, wait for it to connect to VPC Lattice Service Network. 

```bash
kubectl describe gateway ${EKS_CLUSTER_NAME} -n checkout
kubectl wait --for=condition=Programmed gateway/${EKS_CLUSTER_NAME} -n checkout
```

- At this point, you can see the VPC Lattice Service Network on AWS VPC Console / VPC Lattice 

## Route Configuration

- Implement Advanced Traffic Management with weighted routing for
  - Blue/Green deployment
  - Canary deployment
- Deploy a modified version of the checkout microservice (prefix "Lattice") in the shipping options.
- Deploy this new version in a new namespace (checkoutv2) 

```bash
kubectl apply -k ~/environment/eks-workshop/modules/networking/vpc-lattice/abtesting/
kubectl rollout status deployment/checkout -n checkoutv2
```

- Confirm checkoutv2 pods are up and running

```bash
kubectl get pods -n checkoutv2
```

- Create a `TargetGroupPolicy` to let VPC Lattice perform health checks on checkout service:

```bash
cat ~/environment/eks-workshop/modules/networking/vpc-lattice/target-group-policy/target-group-policy.yaml
```

- Create resource

```bash
kubectl apply -k ~/environment/eks-workshop/modules/networking/vpc-lattice/target-group-policy
```

- Create **HTTPRoute** resource with route traffic distribution to two services
  - 75% weight for checkoutv2 (new) and 25% traffic to checkout (old)

```bash
cat ~/environment/eks-workshop/modules/networking/vpc-lattice/routes/checkout-route.yaml
```

- Apply manifest and create resource

```bash
cat ~/environment/eks-workshop/modules/networking/vpc-lattice/routes/checkout-route.yaml \
  | envsubst | kubectl apply -f -
```

- Wait for resource are created and ready

```bash
kubectl wait -n checkout --timeout=3m \
  --for=jsonpath='{.status.parents[-1:].conditions[-1:].reason}'=ResolvedRefs httproute/checkoutroute
```

- Find the HTTPRoute's DNS name from HTTPRoute status
- Look for `Message: DNS Name: line`
- Confirm weight distribution on Amazon VPC Lattice Console page as well

```bash
kubectl describe httproute checkoutroute -n checkout
```

## Testing Canary Traffic Routing

- Test canary deployment is routing 75% of traffic to the new version of the checkout service and 25% to previous version.
- On the web application interface, two UIs of checkout are seen, v2 and v1
- Use Kubernetes `exec` to test the Lattice service URL works from the UI pod 
- Obtain URL from an `annotation` on the **HTTPRoute** resource

```bash
export CHECKOUT_ROUTE_DNS="http://$(kubectl get httproute checkoutroute -n checkout -o json | jq -r '.metadata.annotations["application-networking.k8s.aws/lattice-assigned-domain-name"]')"

echo "Checkout Lattice DNS is $CHECKOUT_ROUTE_DNS"

POD_NAME=$(kubectl -n ui get pods -o jsonpath='{.items[0].metadata.name}')
kubectl exec $POD_NAME -n ui -- curl -s $CHECKOUT_ROUTE_DNS/health
```

- Point the UI service to the VPC Lattice service endpoint by patching the ConfigMap for the UI component

```bash
cat ~/environment/eks-workshop/modules/networking/vpc-lattice/ui/configmap.yaml
```

- Apply the configuration change

```bash
kubectl kustomize ~/environment/eks-workshop/modules/networking/vpc-lattice/ui/ \
  | envsubst | kubectl apply -f -
```

- Restart the UI pods to preview application with Cloud9

```bash
kubectl rollout restart deployment/ui -n ui
kubectl rollout status deployment/ui -n ui
```

- Access the web application using the browser with LoadBalancer DNS

```bash
kubectl get service -n ui ui-nlb -o jsonpath='{.status.loadBalancer.ingress[*].hostname}{"\n"}'
```

# Testing 

- On the browser, using the Load Balancer DNS, the checkout page displays two versions distinguished by the presence of Lattice in one and without it in the other. 
- Feel free to play around with the web application, going through the checkout process like on any shopping website.


# Resource Cleanup

- If CloudFormation fails, delete the dependencies manually and try again.
- On Cloud9 terminal
- Delete the sample application and any left-over lab infrastructure is removed

```bash
delete-environment
```

- On Cloud9 terminal
  - Delete cluster using `eksctl`
  - NOTE: If not deployed any application or built any cluster resources yet, just deleting the cluster is sufficient

```bash
eksctl delete cluster $EKS_CLUSTER_NAME --wait
```

- On CloudShell terminal
- Delete the cloudFormation stack 

```bash
aws cloudformation delete-stack --stack-name eks-workshop-ide
```


# Resources
 
- [AWS Workshop: Amazon VPC Lattice](https://www.eksworkshop.com/docs/networking/vpc-lattice/)
- [AWS Doc: Amazon VPC Lattice](https://docs.aws.amazon.com/eks/latest/userguide/integration-vpc-lattice.html)
- [AWS Doc: What is Amazon VPC Lattice?](https://docs.aws.amazon.com/vpc-lattice/latest/ug/what-is-vpc-lattice.html)
- [AWS Gateway API Controller User Guide](https://www.gateway-api-controller.eks.aws.dev/)
- [Kubernetes Gateway API](https://gateway-api.sigs.k8s.io/)
- [Simplify Service-to-Service Connectivity, Security, and Monitoring with Amazon VPC Lattice – Now Generally Available](https://aws.amazon.com/blogs/aws/simplify-service-to-service-connectivity-security-and-monitoring-with-amazon-vpc-lattice-now-generally-available/)
- [VPC Lattice Features](https://aws.amazon.com/vpc/lattice/features/)
- [Relationship Between VPC Lattice and Kubernetes](https://www.gateway-api-controller.eks.aws.dev/concepts/overview/#relationship-between-vpc-lattice-and-kubernetes)
