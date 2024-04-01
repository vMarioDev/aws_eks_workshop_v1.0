
# Retail Store App Architecture

retail_store_architecture.png



# Deploying the Microservices

- Prepare the Cloud9 environment and EKS cluster for this module

```bash
use-cluster $EKS_CLUSTER_NAME
prepare-environment introduction/getting-started
```

- First, inspect the current namespaces in the EKS cluster

```bash
kubectl get namespace
```

- Check application specific namespaces, there should be none

```bash
kubectl get namespaces -l app.kubernetes.io/created-by=eks-workshop
```

- This application uses **Kustomize** to manage Kubernetes deployments
- The Kustomization manifest lists all the microservices components
- Review all the components by looking inside the YAML file. 
- Expect to see:
  - `catalog`, `carts`, `checkout`, `assets`, `orders`, `ui`, `other`, `rabbitmq`

```bash
cat ~/environment/eks-workshop/base-application/kustomization.yaml
```

- Deploy all the components in one go

```bash
kubectl apply -k ~/environment/eks-workshop/base-application
```

- Check the deployment pods of the `catalog` component
- The status of pods will go through the following states:
  - `ContainerCreating` > `CrashLoopBackOff` > `Running`
- Reason being, the `catalog` Pod shows `CrashLoopBackOff` while `catalog-mysql` is getting ready to provide service. 
- Kubernetes keep restarting meanwhile

```bash
kubectl get pod -n catalog
```

- The `kubectl wait` helps to monitor `Ready` state before issuing other commands

```bash
kubectl wait --for=condition=Ready --timeout=180s pods \
  -l app.kubernetes.io/created-by=eks-workshop -A
```

- Recheck namespaces for application components
- There should be one for each

```bash
kubectl get namespaces -l app.kubernetes.io/created-by=eks-workshop
```
```bash
NAME       STATUS   AGE
assets     Active   2m22s
carts      Active   2m22s
catalog    Active   2m22s
checkout   Active   2m22s
orders     Active   2m22s
other      Active   2m22s
rabbitmq   Active   2m22s
ui         Active   2m22s
```

- Check to confirm that the Deployments are created successfully

```bash
kubectl get deployment -l app.kubernetes.io/created-by=eks-workshop -A
```
```bash
NAMESPACE   NAME             READY   UP-TO-DATE   AVAILABLE   AGE
assets      assets           1/1     1            1           3m15s
carts       carts            1/1     1            1           3m15s
carts       carts-dynamodb   1/1     1            1           3m15s
catalog     catalog          1/1     1            1           3m14s
checkout    checkout         1/1     1            1           3m14s
checkout    checkout-redis   1/1     1            1           3m14s
orders      orders           1/1     1            1           3m14s
orders      orders-mysql     1/1     1            1           3m14s
ui          ui               1/1     1            1           3m14s
```


# Testing Microservices Deployments

- Once pods are up and running, we can check their logs
  - TIP: `-f` option helps to tail the log. Ctrl-C to quit.

```bash
kubectl logs -n catalog -f deployment/catalog
```

- At this points, all pods should be in running state
- For `catalog`, I only deployed 1 replica

```bash
kubectl get pod -n catalog
```

- Use Kubernetes `scale` command to horizontally scale out the number of pods
- Fire both commands together

```bash
kubectl scale -n catalog --replicas 3 deployment/catalog
kubectl wait --for=condition=Ready pods --all -n catalog --timeout=180s
```

- Rollout status check is another way to monitor replica scaling process

```bash
kubectl rollout status deployment/catalog -n catalog
```

- Confirm scaling

```bash
kubectl get pod -n catalog
```

- The manifests also create a **Service** the application and MySQL Pods 
- **Services** are used by other components inside the cluster to connect

```bash
kubectl get svc -n catalog
```

- **Note:** All the Services are internal to the cluster
  - Cannot be accessed from the Internet or even the VPC
- Check the configuration

```bash
cat ~/environment/eks-workshop/base-application/catalog/service.yaml
```

- To connect internally
- The `kubectl exec` is used to connect internally to access an existing Pod
  - The command below invokes the catalog API
  - It pulls a JSON payload with product information

```bash
kubectl -n catalog exec -it \
  deployment/catalog -- curl catalog.catalog.svc/catalogue | jq .
```

# Cleaning UP

- First use delete-environment to remove the sample application and also remove any leftover lab infrastructure

```bash
delete-environment
```

- Delete cluster using `eksctl` in the Cloud9 terminal

```bash
eksctl delete cluster $EKS_CLUSTER_NAME --wait
```

- Delete the cloudformaiton stack from the **CloudShell** terminal

```bash
aws cloudformation delete-stack --stack-name eks-workshop-v1
```


# Resources

- [Architecture of Sample Application](https://www.eksworkshop.com/docs/introduction/getting-started/about/)
- [Microservices on Kubernetes](https://www.eksworkshop.com/docs/introduction/getting-started/microservices/)
- [GitHub source - retail-store-sample-app](https://github.com/aws-containers/retail-store-sample-app)
- [Packaging the components - Dockerfiles](https://www.eksworkshop.com/docs/introduction/getting-started/packaging-application/)
- [Deploying our first component](https://www.eksworkshop.com/docs/introduction/getting-started/first/)
- [Kustomize (optional)](https://www.eksworkshop.com/docs/introduction/kustomize/)
- [Kustomize.io](https://kustomize.io/)
- [Helm](https://helm.sh/)



