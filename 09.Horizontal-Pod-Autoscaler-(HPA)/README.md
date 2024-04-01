# Objectives

- Install Metric Server
- Configure Horizontal Pod Autoscaler





# Install Kubernetes Metrics Server

- Prepare the HPA environment

```bash
prepare-environment autoscaling/workloads/hpa
```

- Confrim Metric Server is ready and running

```bash
kubectl -n kube-system get pod -l app.kubernetes.io/name=metrics-server
```

- If Metrics Server is correctly configured
  - 1. Check the resource (CPU and Memory) consumption for nodes in the cluster

```bash
kubectl top node
```

- 2. Check the resource utilization of pods as well

```bash
kubectl top pod -l app.kubernetes.io/created-by=eks-workshop -A
```

- All set here, Kubernetes Metrics Server is ready on Amazon EKS Cluster

# Configure Horizontal Pod Autoscaler


- Check if any current workload has enabled HPA in the cluster
- Expect nothing yet

```bash
kubectl get hpa
```

- This workshop example plans to scale the UI service based on CPU usage
- First the workload manifest is updated to use CPU resource request and limit

```bash
cat ~/environment/eks-workshop/modules/autoscaling/workloads/hpa/deployment.yaml
```

- Then, define the HorizontalPodAutoscaler resource
- Specify the metric used by HPA to control the scaling operation

```bash
cat ~/environment/eks-workshop/modules/autoscaling/workloads/hpa/hpa.yaml
```

- Appy the manifests 

```bash
kubectl apply -k ~/environment/eks-workshop/modules/autoscaling/workloads/hpa
```

- Confirm HPA is running at this point

```bash
kubectl get hpa
```


# Generate Load and Test HPA


- With the load generation on, we can patiently watch how the CPU consumption grows, exceeding the limit specified in the HPA configuration (80%). 
- As a result, the HPA controller increases the replica count from a minimum of 1 to max count of 4. 
- As soon as the load generation stops, CPU consumption subsides and the replica count goes back to the minimum count.
- This load generator used 10 workers, sending 5 q/s, running max 60 minutes

```bash
kubectl run load-generator \
  --image=williamyeh/hey:latest \
  --restart=Never -- -c 10 -q 5 -z 60m http://ui.ui.svc/home
```

- Watch HPA
  - As load increases and CPU consumption exceeds 80%, more pods are created
  - Replica count stabilizes once actual consumption falls below target

```bash
kubectl get hpa ui -n ui --watch

```

- Kill load generator after sufficient pods are running meeting target metric
- Eventually the scale down happens, replica count going back to minimum

```bash
kubectl delete pod load-generator
```







# Resources

- [Horizontal Pod Autoscaling](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/)
- [HorizontalPodAutoscaler Walkthrough](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale-walkthrough/)
- [Resource metrics pipeline](https://kubernetes.io/docs/tasks/debug/debug-cluster/resource-metrics-pipeline/)
- [Kubernetes Metrics Server](https://github.com/kubernetes-sigs/metrics-server)
- [Generate Load: Hey Software](https://github.com/rakyll/hey)