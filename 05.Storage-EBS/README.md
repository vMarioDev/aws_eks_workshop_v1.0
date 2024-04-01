# Objectives

- Deploying a Stateful Application with StatefulSet Workload
- Installing EBS Container Storage Interface (CSI) Driver

# Deploying a Stateful Application

- The `StatefulSet` maintains a sticky identity for each of its Pods and these pods are created from the same `spec`, but are not interchangeable because each has a persistent identifier that it maintains across any rescheduling.
- `StatefulSets` is the solution when persistent storage across workload pods is needed and unavoidable. 
- Individual Pods in a `StatefulSet`, like in the Deployment workload, are susceptible to failure but the persistent Pod identifiers match existing volumes to the newly replaced Pods when that occurs for a variety of reasons.
- Prepare the environment
  - It installs the microservices of the `StatefulSet` based ecommerce application
  - It create the IAM role needed for the EBS CSI driver addon
    - AWS Ref: https://docs.aws.amazon.com/eks/latest/userguide/csi-iam-role.html

```bash
prepare-environment fundamentals/storage/ebs
```

- The **Catalog** microservice of the application has a `StatefulSet` deployed 
- It utilizes a persistent storage MySQL database running on the EKS cluster
- Examine the pods of the `catalog` microservice. Only one pod provisioned.

```bash
kubectl get pods -n catalog -l app.kubernetes.io/component=mysql
```

- Peek under the hood of the `StatefulSet` workload running on one pod only

```bash
kubectl -n catalog get statefulset catalog-mysql -o yaml
```

- Let's look at the Volume configuration of the StatefulSet workload
- Expect to see an `emptyDir` volume type

```bash
kubectl -n catalog describe statefulset catalog-mysql
```

## Testing Non-Persistent Storage


- Using `emptyDir` volume means it only "shares the Pod's lifetime".
  - If the pod is gone the volume is gone
  - During its existence, all containers in the pod will have access to it

```bash
kubectl -n catalog describe statefulset catalog-mysql | grep -i -A 4 Volumes
```

- To prove `emptyDir` vanishes along with the pod
  - Write a file on the `emptyDir` volume from within the pod

```bash
kubectl -n catalog exec catalog-mysql-0 -- bash -c \
  "echo 'emptyDir test file: I'll vanish when this pod terminates!!' > /var/lib/mysql/test.txt"
```

- Verify the test file listing and content

```bash
kubectl -n catalog exec catalog-mysql-0 -- ls -larth /var/lib/mysql/ \
    | grep -i test

kubectl -n catalog exec catalog-mysql-0 -- cat /var/lib/mysql/test.txt
```

- Force delete the pod of the StatefulSet workload and wait for the pod to be recreated to maintain replica count

```bash
kubectl -n catalog delete pods -l app.kubernetes.io/component=mysql

kubectl -n catalog wait --for=condition=Ready pod \
  -l app.kubernetes.io/component=mysql --timeout=30s
```

- Confirm new pod was recreated from the `Age` column

```bash
kubectl -n catalog get pods -l app.kubernetes.io/component=mysql
```

- Reverify the test file listing and content
  - Expect no listing and no such file error since the last 
  - `emptyDir` file vanished along with its host pod

```bash
kubectl -n catalog exec catalog-mysql-0 -- ls -larth /var/lib/mysql/ \
    | grep -i test

kubectl -n catalog exec catalog-mysql-0 -- cat /var/lib/mysql/test.txt
```


# Installing EBS CSI


- CSI (Container Storage Interface) like other Kubernetes Interfaces, CNI (Kubernetes Network Interface) for instance, enables the open plug-and-play architecture possible, providing the choice of selecting different kinds of storage from a wide variety of cloud providers and vendors.
- Install the EBS CSI driver add-on 
  - It takes few minutes for the EBS Volume to come up

```bash
aws eks create-addon --cluster-name $EKS_CLUSTER_NAME \
  --addon-name aws-ebs-csi-driver \
  --service-account-role-arn $EBS_CSI_ADDON_ROLE

aws eks wait addon-active --cluster-name $EKS_CLUSTER_NAME \
  --addon-name aws-ebs-csi-driver
```

- Review what has been created in our EKS cluster by the addon
- Expect to see 
  - 1. An EBS CSI controller deployment
  - 2. A DaemonSet (DaemonSet/ebs-csi-node)

```bash
kubectl -n kube-system get pods | grep ebs-csi
```

- Check the Deployment with 2 pods

```bash
kubectl -n kube-system get deployment/ebs-csi-controller
```

- Check the DaemonSet with 3 pods, one on each node in the EKS cluster

```bash
kubectl -n kube-system get daemonset/ebs-csi-node
```

- Check the StorageClass object configured 
- Expect a AWS EBS `gp2` storage class
- Dynamic Provisioning means it's waiting for its first 

```bash
kubectl get storageclass
```

# Provisioning EBS Persistent Volumes

- Provision Amazon EBS volumes on demand via the [Dynamic Volume Provisioning (DVP)](https://github.com/kubernetes-sigs/aws-ebs-csi-driver/tree/master/examples/kubernetes/dynamic-provisioning) capability in our EKS cluster. 
- Review the `.spec.volumeClaimTemplates` in the below manifest which performs this magic by leveraging the EBS CSI.
- Two goals here:
  - 1. Create a new StatefulSet for the MySQL database used by the `catalog` component which uses an EBS volume
  - 2. Update the `catalog` component to use the new version of the database
- Review manifest of a new `StatefulSet` to be created

```bash
cat ~/environment/eks-workshop/modules/fundamentals/storage/ebs/statefulset-mysql.yaml
```

- Reconfigure the catalog component to use the new StatefulSet

```bash
cat ~/environment/eks-workshop/modules/fundamentals/storage/ebs/deployment.yaml
```

- Apply the changes and wait for the new pods to be ready

```bash
kubectl apply -k ~/environment/eks-workshop/modules/fundamentals/storage/ebs/
kubectl -n catalog rollout status --timeout=100s statefulset/catalog-mysql-ebs
```

- Confirm the new `StatefulSet` is running

```bash
kubectl -n catalog get statefulset catalog-mysql-ebs
```

- Inspecting the `catalog-mysql-ebs` StatefulSet
  - We can see that now we have a `PersistentVolumeClaim` attached to it with 30GiB and with `storageClassName` of `gp2`.
- Confirm, we have `PersistentVolumeClaim` attached to the `StatefulSet`
- Expect to see the `StorageClass` create in the previous section

```bash
kubectl -n catalog get statefulset catalog-mysql-ebs \
  -o jsonpath='{.spec.volumeClaimTemplates}' | jq .
```

- Checking the PVC and the PV created by Dynamic Volume Provisioning

```bash
kubectl -n catalog get pvc
kubectl get pv
kubectl describe pv
```

- View the Amazon EBS volume created automatically
- Check the references for verification and connect the dots:
  - 1. VolumeID from the PV description above
  - 2. PVC from `kubernetes.io/created-for/pvc/name` key in the output

```bash
aws ec2 describe-volumes \
    --filters Name=tag:kubernetes.io/created-for/pvc/name,Values=data-catalog-mysql-ebs-0 \
    --query "Volumes[*].{ID:VolumeId,Tag:Tags}" \
    --no-cli-page
```

- We can go inside the container and examine the volume filesystem
- Expect to see the disk mounted to directory `/var/lib/mysql`
- This is a persistent storage that we'll venture to prove next

```bash
kubectl -n catalog exec --stdin catalog-mysql-ebs-0 -- bash -c "df -h"
```

- Verify the persistent storage with EBS Volume
- 1. Create a `test.txt` file like before

```bash
kubectl -n catalog exec catalog-mysql-ebs-0 -- bash -c \
  "echo 'EBS persistent store test file; I will persist!!' > /var/lib/mysql/test.txt"
```

- 2. Verify that the test.txt file was created on the /var/lib/mysql directory

```bash
kubectl -n catalog exec catalog-mysql-ebs-0 -- ls -larth /var/lib/mysql/ \
    | grep -i test

kubectl -n catalog exec catalog-mysql-ebs-0 -- cat /var/lib/mysql/test.txt
```

- 3. Force remove the current `catalog-mysql-ebs` pod to trigger the `StatefulSet` controller to automatically re-create a new pod

```bash
kubectl -n catalog delete pods catalog-mysql-ebs-0
```

- Wait for `catalog-mysql-ebs` Pod to be created and ready


```bash
kubectl -n catalog wait --for=condition=Ready pod \
  -l app.kubernetes.io/component=mysql-ebs --timeout=60s
```

- Confirm new pod by looking at AGE 

```bash
kubectl -n catalog get pod catalog-mysql-ebs-0 
```

- Exec back into the MySQL container shell and verify the file from the previous pod persists in the new pod

```bash
kubectl -n catalog exec catalog-mysql-ebs-0 -- ls -larth /var/lib/mysql/ \
    | grep -i test

kubectl -n catalog exec catalog-mysql-ebs-0 -- cat /var/lib/mysql/test.txt
```


# Resources

- [AWS Workshop: Storage](https://www.eksworkshop.com/docs/fundamentals/storage/)
- [Kubernetes Storage](https://kubernetes.io/docs/concepts/storage/)
- [Amazon Elastic Block Store (EBS) CSI driver](https://github.com/kubernetes-sigs/aws-ebs-csi-driver)
- [Kubernetes Workloads](https://kubernetes.io/docs/concepts/workloads/)
- [Demonstrating emptyDir Ephemeral Volumes](https://medium.com/the-aws-way/mastering-kubernetes-one-task-at-a-time-ephemeral-storage-volumes-with-emptydir-6cb08546b0ff)
- [Container Storage Interface (CSI) for Kubernetes GA](https://kubernetes.io/blog/2019/01/15/container-storage-interface-ga/)
- [Dynamic Volume Provisioning](https://github.com/kubernetes-sigs/aws-ebs-csi-driver/tree/master/examples/kubernetes/dynamic-provisioning)