# Objectives

- Expose the application using Network Load Balancer by leveraging the **AWS Cloud Controller Manager**’s capability to create a load balancer with the Service `type: LoadBalancer` directive.



# Network Load Balancer — Instance Mode

- Prepare the environment

```bash
prepare-environment exposing/load-balancer
```

- Confirm all the microservices are only accessible internally

```bash
kubectl get svc -l app.kubernetes.io/created-by=eks-workshop -A
```

- Review the current UI service
- Observe line, `type: ClusterIP`

```bash
cat ~/environment/eks-workshop/base-application/ui/service.yaml 
```

- Check the details of the UI Service object since it's already created

```bash
kubectl -n ui describe service ui
```

- Verify that the UI service endpoint above points to UI pods
  - only one pod running at this point

```bash
kubectl get pods -n ui -o wide
```

- Review the additional new Service to provisions a load balancer
- Observe line with `type: LoadBalancer`

```bash
cat ~/environment/eks-workshop/modules/exposing/load-balancer/nlb/nlb.yaml
```

- Create the new UI Service object
- This Service by design creates a Network Load Balancer 
- It listens on port 80 and forwards connections to the UI Pods on 8080

```bash
kubectl apply -k \
    ~/environment/eks-workshop/modules/exposing/load-balancer/nlb
```

- Now inspect the Service resources in the UI namespace
- Expect to see two separate resources
  - (1) The new `ui-nlb` has `type LoadBalancer`
  - (2) It also has an `external IP` value, takes few minutes to appear
  - (3) EXTERNAL-IP field has the load balancer DNS name 
  - (4) This provides access to the application from the outside world

```bash
kubectl get service -n ui
```

- Examine the `ui-nlb` service deeper
- Annotations are of interest here 
- See AWS Load Balancer Controller (Network Load Balancer) explanation above

```bash
kubectl describe service ui-nlb -n ui
```

- Examine the load balancer details to confirm
  - The NLB is accessible over the public internet
  - It uses the public subnets in the VPC
  - The DNSName key has the value reported in the previous command

```bash
aws elbv2 describe-load-balancers \
--query 'LoadBalancers[?contains(LoadBalancerName, `k8s-ui-uinlb`) == `true`]'
```

- Inspect the targets in the target group that was created by the controller
- Expect to see 3 targets (EC2 instances) registered to the load balancer
- The three targets are the three cluster nodes

```bash
ALB_ARN=$(aws elbv2 describe-load-balancers --query 'LoadBalancers[?contains(LoadBalancerName, `k8s-ui-uinlb`) == `true`].LoadBalancerArn' | jq -r '.[0]')
TARGET_GROUP_ARN=$(aws elbv2 describe-target-groups --load-balancer-arn $ALB_ARN | jq -r '.TargetGroups[0].TargetGroupArn')
aws elbv2 describe-target-health --target-group-arn $TARGET_GROUP_ARN
```

- Handy command to wait until the load balancer has finished provisioning

```bash
wait-for-lb $(kubectl get service -n ui ui-nlb -o jsonpath="{.status.loadBalancer.ingress[*].hostname}{'\n'}")
```

- Obtain the externally accessible load balancer URL

```bash
kubectl get service -n ui ui-nlb -o jsonpath="{.status.loadBalancer.ingress[*].hostname}{'\n'}"
```

# Creating the Network Load Balancer — IP Mode

- Prepare the environment

```bash
prepare-environment exposing/load-balancer
```

- Review the service manifest for ip mode

```bash
cat ~/environment/eks-workshop/modules/exposing/load-balancer/ip-mode/nlb.yaml
```

- Apply the manifest with kustomize

```bash
kubectl apply -k ~/environment/eks-workshop/modules/exposing/load-balancer/ip-mode
```

- Confirm the annotation has been updated

```bash
kubectl describe service/ui-nlb -n ui
```

- Let's look at the the targets in the target group of the load balancer
- Expect to see only one `IP` as the target, the IP of the `ui` pod

```bash
ALB_ARN=$(aws elbv2 describe-load-balancers --query 'LoadBalancers[?contains(LoadBalancerName, `k8s-ui-uinlb`) == `true`].LoadBalancerArn' | jq -r '.[0]')
TARGET_GROUP_ARN=$(aws elbv2 describe-target-groups --load-balancer-arn $ALB_ARN | jq -r '.TargetGroups[0].TargetGroupArn')
aws elbv2 describe-target-health --target-group-arn $TARGET_GROUP_ARN
```

- We can scale up the ui component to 3 replicas to create more pods

```bash
kubectl scale -n ui deployment/ui --replicas=3
kubectl wait --for=condition=Ready pod -n ui -l app.kubernetes.io/name=ui --timeout=60s
```

- Let's examine the targets of the load balancer after the scale out

```bash
aws elbv2 describe-target-health --target-group-arn $TARGET_GROUP_ARN
```

- Wait until the load balancer finish the reconfiguration

```bash
wait-for-lb $(kubectl get service -n ui ui-nlb -o jsonpath="{.status.loadBalancer.ingress[*].hostname}{'\n'}")
```

- Obtain the externally accessible load balancer URL

```bash
kubectl get service -n ui ui-nlb -o jsonpath="{.status.loadBalancer.ingress[*].hostname}{'\n'}"
```







# Resources

- [Services, Load Balancing, and Networking](https://kubernetes.io/docs/concepts/services-networking/)
- [AWS Load Balancer Controller](https://www.eksworkshop.com/docs/fundamentals/exposing/aws-lb-controller/)
- [How AWS Load Balancer controller works](https://kubernetes-sigs.github.io/aws-load-balancer-controller/v2.6/how-it-works/)
- [Network Load Balancer](https://kubernetes-sigs.github.io/aws-load-balancer-controller/v2.6/guide/service/nlb/)
- [Service controller](https://kubernetes.io/docs/concepts/architecture/cloud-controller/#service-controller)
- [Well-Known Labels, Annotations and Tains](https://kubernetes.io/docs/reference/labels-annotations-taints/#service-beta-kubernetes-io-aws-load-balancer-scheme)
- [IP Mode](https://www.eksworkshop.com/docs/fundamentals/exposing/loadbalancer/ip-mode/)


