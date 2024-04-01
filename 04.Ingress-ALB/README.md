# Objectives

- Expose thr Application using Ingress, where the **Application Load Balancer:** 
  - Controls external traffic routing, operating in Application Layer 7
  - Performing URL path-based routing to different services as defined in the ingress resource objects, and meeting other key networking and security needs.


# Single Ingress Pattern

- An ingress is just a configuration object containing the traffic routing rules.
- The **Ingress Controller** (AWS Load Balancer Controller) forwards the client requests to the target Kubernetes service.
- The **Ingress Controller** needs to be deployed independently as it is not provided as part of the Kube Controller Manager or Cloud Controller Manager.
- Prepare the environment

```bash
prepare-environment exposing/ingress
```

- Check that there are no Ingress resources in the cluster yet!

```bash
kubectl get ingress -n ui
```

- There are also no Service resources of type LoadBalancer either

```bash
kubectl get svc -n ui
```

- We do have all the microservices, accessible internally, inside the cluster

```bash
kubectl get svc -l app.kubernetes.io/created-by=eks-workshop -A
```

- Let's create the ingress that will route traffic to the UI service
- Review the YAML manifest

```bash
cat ~/environment/eks-workshop/modules/exposing/ingress/creating-ingress/ingress.yaml
```

- Apply ingress manifest

```bash
kubectl apply -k ~/environment/eks-workshop/modules/exposing/ingress/creating-ingress
```

- Inspect the Ingress object created
- As it shows, the ALB creation is already in progress

```bash
kubectl get ingress ui -n ui

# Or

kubectl describe ingress -n ui
```

- Wait for the load balancer to finish provisioning
- And get the load balancer URL to access our application externally

```bash
wait-for-lb $(kubectl get ingress -n ui ui -o jsonpath="{.status.loadBalancer.ingress[*].hostname}{'\n'}")
```

- We can examing the configuration of this ALB
  - `Scheme` field suggets the ALB is accessible over the public internet
  - Subnet IDs point to public subnets in the VPC

```bash
aws elbv2 describe-load-balancers --query 'LoadBalancers[?contains(LoadBalancerName, `k8s-ui-ui`) == `true`]'
```

- Inspect the targets in the target group of the ALB
- Expect to see only one `IP` as the target, the IP of the `ui` pod

```bash
ALB_ARN=$(aws elbv2 describe-load-balancers --query 'LoadBalancers[?contains(LoadBalancerName, `k8s-ui-ui`) == `true`].LoadBalancerArn' | jq -r '.[0]')
TARGET_GROUP_ARN=$(aws elbv2 describe-target-groups --load-balancer-arn $ALB_ARN | jq -r '.TargetGroups[0].TargetGroupArn')
aws elbv2 describe-target-health --target-group-arn $TARGET_GROUP_ARN
```

- Scale up the ui component to 3 replicas to create more pods

```bash
kubectl scale -n ui deployment/ui --replicas=3
kubectl wait --for=condition=Ready pod -n ui -l app.kubernetes.io/name=ui --timeout=60s
```

- Examine the targets of the load balancer after the scale out
- Expect to see 3 targets pointing to 3 scaled up pods

```bash
aws elbv2 describe-target-health --target-group-arn $TARGET_GROUP_ARN
```

- Same with the ingress object as well, it has 3 backend IPs

```bash
kubectl describe ingress -n ui
```

# Multiple Ingress Pattern

- Most microservices-based Kubernetes applications will have multiple ingress objects managing a multitude of services and deployments handled by a single load balancer (ALB). 
- To avoid creating a separate ALB for each Ingress, the **IngressGroup** feature groups multiple ingress rules, and a single ALB handles all the routing. 
- Implementation-wise, the `alb.ingress.kubernetes.io/group.name` annotation is where the group magic happens.
- In Web Store application, expose the `catalog` API out through the same ALB as the `ui` component, and leverage `path-based` routing to send requests to the appropriate deployment pod via the corresponding service.
- Confirm that the catalog API is not accessible via the ALB
  - Expect to see 404 response

```bash
ADDRESS=$(kubectl get ingress -n ui ui -o jsonpath="{.status.loadBalancer.ingress[*].hostname}{'\n'}")
curl $ADDRESS/catalogue
```

- Modify the UI Ingress
- By adding the annotation `alb.ingress.kubernetes.io/group.name`

```bash
cat ~/environment/eks-workshop/modules/exposing/ingress/multiple-ingress/ingress-ui.yaml
```

- Create the Catalog Ingress with the same `group.name` used above
- And with rules to route `/catalogue` requests to the `catalog` service

```bash
cat ~/environment/eks-workshop/modules/exposing/ingress/multiple-ingress/ingress-catalog.yaml
```

- Create the ingress objects

```bash
kubectl apply -k ~/environment/eks-workshop/modules/exposing/ingress/multiple-ingress
```

- Confirm two separate ingress objects exist in the cluster
- Expect to see both pointing to the same URL address
- Meaning the IngressGroup is doing its job of merging multiple ingress rules

```bash
kubectl get ingress -l app.kubernetes.io/created-by=eks-workshop -A
```

- Issue the usual wait command until the load balancer is done provisioning

```bash
wait-for-lb $(kubectl get ingress -n ui ui -o jsonpath="{.status.loadBalancer.ingress[*].hostname}{'\n'}")
```

- Examing the ALB listener under the hood
- Observe:
  - (1) Requests with path prefix `/catalogue` are routed to `catalog` service
  - (2) Everything are routed to a target group for the `ui` service
  - (3) A default 404 response if any requests fall through the cracks

```bash
ALB_ARN=$(aws elbv2 describe-load-balancers --query 'LoadBalancers[?contains(LoadBalancerName, `k8s-retailappgroup`) == `true`].LoadBalancerArn' | jq -r '.[0]')
LISTENER_ARN=$(aws elbv2 describe-listeners --load-balancer-arn $ALB_ARN | jq -r '.Listeners[0].ListenerArn')
aws elbv2 describe-rules --listener-arn $LISTENER_ARN
```

- The new Ingress URL in a browser should pull the application successfully!

```bash
kubectl get ingress -n ui ui -o jsonpath="{.status.loadBalancer.ingress[*].hostname}{'\n'}"
```

- To test `catalog` service, append the prefix `/catalogue` at the end of the URL
- Expect to receive back a JSON payload from the `catalog` service

```bash
ADDRESS=$(kubectl get ingress -n ui ui -o jsonpath="{.status.loadBalancer.ingress[*].hostname}{'\n'}")
curl $ADDRESS/catalogue | jq .
```




# Resources

- [AWS Load Balancer Controller - Ingress annotations](https://kubernetes-sigs.github.io/aws-load-balancer-controller/v2.6/guide/ingress/annotations/)
- [Services, Load Balancing, and Networking](https://kubernetes.io/docs/concepts/services-networking/)
