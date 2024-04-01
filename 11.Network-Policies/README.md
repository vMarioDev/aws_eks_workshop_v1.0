# Objectives

- Network Policy Implementation

diagram.png

# Implementing Egress Controls

- Prepare the environment

```bash
prepare-environment networking/network-policies
```

- At this point in the cluster:
  - There are no network policies that are defined
  - So any component in the webapp application can communicate with any other component or any external service
- Verify the claim by talking to another service from a **Catalog** pod
- Expect this to work

```bash
kubectl exec deployment/catalog -n catalog -- curl -s http://checkout.checkout/health
```

- Verify another communication from **UI** to **Catalog** service
- Expect this to work as well

```bash
kubectl exec deployment/ui -n ui -- curl -s http://catalog.catalog/health --connect-timeout 5
```

- Block all egress traffic from `ui` namespace
- Define a generic network policy without specifying any namespace
- This Network policy can be applied to any namespace in the cluster

```bash
cat ~/environment/eks-workshop/modules/networking/network-policies/apply-network-policies/default-deny.yaml
```

- Apply the network policy

```bash
kubectl apply -n ui -f ~/environment/eks-workshop/modules/networking/network-policies/apply-network-policies/default-deny.yaml
```

- Try again the above two examples
- **Catalog** to **checkout** should work just fine
- No Network Policy applied here yet

```bash
kubectl exec deployment/catalog -n catalog -- curl -s http://checkout.checkout/health
```

- **UI** to any other pod or service should be blocked
- This command should time out, all outbound connctions blocked off

```bash
kubectl exec deployment/ui -n ui -- curl -s http://catalog.catalog/health --connect-timeout 5
```

- Create a Network Policy to allow **UI** pods to communicate with
  - 1. All other application services
  - 2. Al components in the `kube-system` namespace

```bash
cat ~/environment/eks-workshop/modules/networking/network-policies/apply-network-policies/allow-ui-egress.yaml
```

- Apply `allow-ui-egress` network policy 

```bash
kubectl apply -f ~/environment/eks-workshop/modules/networking/network-policies/apply-network-policies/allow-ui-egress.yaml
```


- Try again communication to catalog service as well as the checkout service
- Expect both to work

```bash
kubectl exec deployment/ui -n ui -- curl http://catalog.catalog/health
kubectl exec deployment/ui -n ui -- curl http://checkout.checkout/health
```

- All communicaiton to any external site or service will not work however
- Because of restricted connections allowed, everything else is blocked

```bash
kubectl exec deployment/ui -n ui -- curl -v www.google.com --connect-timeout 5
```


# Implementing Ingress Controls

- Based on the microservice architecture diagram:
  - 1. The `catalog` namespace receives traffic only from the `ui` namespace and from no other namespace.
  - 2. The `catalog` database component can only receive traffic from the `catalog` service component, and from nowhere else
- Both restrictions can be controlled by Network Policies
- Before restricting, test if the communication is open
  - 1. From **UI** to **Catalog**
  - 2. From **Order** to **Catalog**
  - 3. From **Order** to **Catalog** Database component
- All should work

```bash
kubectl exec deployment/ui -n ui -- curl -v catalog.catalog/health --connect-timeout 5

kubectl exec deployment/orders -n orders -- curl -v catalog.catalog/health --connect-timeout 5

kubectl exec deployment/orders -n orders -- curl -v telnet://catalog-mysql.catalog:3306 --connect-timeout 5
```

- Define a network policy that will allow traffic into (ingress) the `catalog` service component only from the `ui` component

```bash
cat ~/environment/eks-workshop/modules/networking/network-policies/apply-network-policies/allow-catalog-ingress-webservice.yaml
```

- Apply network policy

```bash
kubectl apply -f ~/environment/eks-workshop/modules/networking/network-policies/apply-network-policies/allow-catalog-ingress-webservice.yaml
```

- Test access
  - 1. From UI to Catalog, this should work fine

```bash
kubectl exec deployment/ui -n ui -- curl -v catalog.catalog/health --connect-timeout 5
```

- Test access
  - 2. From Order to Catalog, this should be blocked

```bash
kubectl exec deployment/orders -n orders -- curl -v catalog.catalog/health --connect-timeout 5
```

- The `catalog` database component is still open
- Define a Network Policy to only **Catalog** service can communicate with **Catalog** database component

```bash
cat ~/environment/eks-workshop/modules/networking/network-policies/apply-network-policies/allow-catalog-ingress-db.yaml
```

- Apply Network Policy

```bash
kubectl apply -f ~/environment/eks-workshop/modules/networking/network-policies/apply-network-policies/allow-catalog-ingress-db.yaml
```

- Test network policy restriction is in place
- Communication from `catalog` database from the `orders` component should fail and also from UI pods it should fail

```bash
kubectl exec deployment/orders -n orders -- curl -v telnet://catalog-mysql.catalog:3306 --connect-timeout 5
kubectl exec deployment/ui -n ui -- curl -v telnet://catalog-mysql.catalog:3306 --connect-timeout 5
```

- Test network policy restriction doesn't apply to `catalog` namespace
- Access works from existing pods from the catalog namespace

```bash
kubectl exec deployment/catalog -n catalog -- curl -v telnet://catalog-mysql.catalog:3306 --connect-timeout 5
```

- Access works from existing pods from the `catalog` namespace with new pods after a restart

```bash
kubectl rollout restart deployment/catalog -n catalog
kubectl rollout status deployment/catalog -n catalog --timeout=2m
kubectl exec deployment/catalog -n catalog -- curl -v telnet://catalog-mysql.catalog:3306 --connect-timeout 5
```

# Network Policy Debugging

- Network policy agent logs are available in the file `/var/log/aws-routed-eni/network-policy-agent.log` on each worker node and provide clues to debug any connection anomaly
- These logs can also be streamed to **Amazon CloudWatch** service and viewed with **CloudWatch Container Insights** feature to glean insights on the **Network Policy** usage and activity.
- Amazon VPC CNI provides logs that can be used to debug issues while implementing networking policies.
- Implementing an ingress network policy that will restrict access to the `orders` service `component` from `ui` component only (similar to policy applied to `catalog` service component previously)

```bash
cat ~/environment/eks-workshop/modules/networking/network-policies/apply-network-policies/allow-order-ingress-fail-debug.yaml
```

- Apply policy

```bash
kubectl apply -f ~/environment/eks-workshop/modules/networking/network-policies/apply-network-policies/allow-order-ingress-fail-debug.yaml
```

- Test **UI** to **Order** service. It should succeed ideally

```bash
kubectl exec deployment/ui -n ui -- curl -v orders.orders/orders --connect-timeout 5
```

- The above communication didn't work
- Check Network Policy log available in each node under `/var/log/aws-routed-eni/network-policy-agent.log` 
- Expect to see `DENY` from **UI** pods
- `kubectl debug --help` for more information

```bash
POD_HOSTIP_1=$(kubectl get po --selector app.kubernetes.io/component=service -n orders -o json | jq -r '.items[0].spec.nodeName')
kubectl debug node/$POD_HOSTIP_1 -it --image=ubuntu
```

- Run this from within the container shell

```bash
grep DENY /host/var/log/aws-routed-eni/network-policy-agent.log | tail -5
```

- Exit from container after `grep`
- Check Network Policy manifest 
  - `namespaceSelector` is empty, which means only the current namespace is permitted (orders)
- Fix network policy

```bash
cat ~/environment/eks-workshop/modules/networking/network-policies/apply-network-policies/allow-order-ingress-success-debug.yaml
```

- Apply fixed manifest

```bash
kubectl apply -f ~/environment/eks-workshop/modules/networking/network-policies/apply-network-policies/allow-order-ingress-success-debug.yaml
```

- Retest UI to Order service. It should succeed!

```bash
kubectl exec deployment/ui -n ui -- curl -v orders.orders/orders --connect-timeout 5
```

# Resources

- [AWS Workshop: Hands on with EKS Networking (2023)](https://youtu.be/EAZnXII9NTY)
- [Amazon VPC CNI](https://www.eksworkshop.com/docs/networking/vpc-cni/)
- [EKS Workshop: Network Policies](https://www.eksworkshop.com/docs/networking/vpc-cni/network-policies/)
- [Working with the Amazon VPC CNI plugin for Kubernetes Amazon EKS add-on](https://docs.aws.amazon.com/eks/latest/userguide/managing-vpc-cni.html)
- [Alternate compatible CNI plugins](https://docs.aws.amazon.com/eks/latest/userguide/alternate-cni-plugins.html)
- [Amazon VPC CNI Plugins](https://github.com/aws/amazon-vpc-cni-plugins)
- [Cluster Networking](https://kubernetes.io/docs/concepts/cluster-administration/networking/)
- [Network Policies](https://kubernetes.io/docs/concepts/services-networking/network-policies/)
- [Network Plugins](https://kubernetes.io/docs/concepts/extend-kubernetes/compute-storage-net/network-plugins/)
- [NetworkPolicy v1 networking.k8s.io](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.29/#networkpolicy-v1-networking-k8s-io)
- [How nodes handle container logs](https://kubernetes.io/docs/concepts/cluster-administration/logging/#how-nodes-handle-container-logs)
- [Troubleshooting Tips](https://github.com/aws/amazon-vpc-cni-k8s/blob/master/docs/troubleshooting.md)




