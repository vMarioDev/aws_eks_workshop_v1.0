# Objectives

- Implement Amazon’s Elastic File System, the fully managed, serverless, and scalable elastic file system designed to handle storage needs of big data analytics, web server storage, content management, and myriad other needs dependent on NFS (Network File System) storage system which can be pre-populated with data, and that data can be shared between pods.


# EFS CSI Driver

- Two primary requirements:
  - Amazon Elastic File System Container Storage Interface (CSI) Driver installation
  - Manual creation of AWS EFS file system
    - EFS CSI driver supports **static** and **dynamic** provisioning:
      - For **static provisioning**, EFS is created manually and then mounted inside a container as a **volume** using the driver.
      - **Dynamic provisioning** creates an access point for each `PersistentVolume` for a given **EFS Kubernetes Storage Class**.
- Prepare EFS environment for the microservices application

```bash
prepare-environment fundamentals/storage/efs
```

- Verify installation of Amazon EFS (CSI) Driver 
- Expect to see `efs-csi-node` daemonset is running on each node (total 3)

```bash
kubectl get daemonset efs-csi-node -n kube-system
```

- Verify and retrieve the EFS_ID to be used later

```bash
export EFS_ID=$(aws efs describe-file-systems --query "FileSystems[?Name=='$EKS_CLUSTER_NAME-efs-assets'] | [0].FileSystemId" --output text)
```

# Pod File Data Sharing

- Create of the Kubernetes **StorageClass** reflecting **dynamic provisioning** mode via its `provisioningMode` parameter, **PersistentVolumeClaim (PVC)**, and a deployment to mount the PVC to the shared storage location.
- Create a **StorageClass** and use EFS Access points in provisioning mode.

```bash
# Review EFS SC manifest
cat ~/environment/eks-workshop/modules/fundamentals/storage/efs/storageclass/efsstorageclass.yaml
```

- Create EFS Storage Class object

```bash
kubectl kustomize \
  ~/environment/eks-workshop/modules/fundamentals/storage/efs/storageclass \
  | envsubst | kubectl apply -f-
```

- Confirm StorageClass creation and take note of:
  - 1. Provisioner is EFS CSI driver 
  - 2. Provisioning mode is EFS access point 
  - 3. EFS_ID is the manually created EFS


```bash
kubectl get storageclass
```

- Next, modify the asset microservice to use the EFS StorageClass 
- First review the PVC manifest and the paremeters

```bash
cat ~/environment/eks-workshop/modules/fundamentals/storage/efs/deployment/efspvclaim.yaml
```

- Review deployment manifest where we're
  - 1. Mounting the PVC to the location where the assets images are stored
  - 2. Add an `init` container to copy the initial images to the EFS volume

```
cat ~/environment/eks-workshop/modules/fundamentals/storage/efs/deployment/deployment.yaml
```

- Create deployment

```bash
kubectl apply -k \
  ~/environment/eks-workshop/modules/fundamentals/storage/efs/deployment
```

- Check `mountPath` values in the deployment object

```bash
kubectl get deployment -n assets \
  -o yaml | yq '.items[].spec.template.spec.containers[].volumeMounts' 
```

- A PersistentVolume (PV) automatically created for the PersistentVolumeClaim (PVC)

```bash
kubectl get pv
```

- Review PersistentVolumeClaim (PVC) created

```bash
kubectl describe pvc -n assets
```

- Create a new file newproduct.png under the assets directory in the first Pod

```bash
POD_NAME=$(kubectl -n assets get pods -o jsonpath='{.items[0].metadata.name}')
kubectl exec --stdin $POD_NAME \
  -n assets -c assets -- bash -c 'touch /usr/share/nginx/html/assets/newproduct.png'
```

- Then verify that the file now also exists in the second Pod
- To confirm the file sharing across pods is happening on EFS 

```bash
POD_NAME=$(kubectl -n assets get pods -o jsonpath='{.items[1].metadata.name}')
kubectl exec --stdin $POD_NAME \
  -n assets -c assets -- bash -c 'ls /usr/share/nginx/html/assets'
```

- Successfully created a file through the first Pod and tested its availability and access on the second Pod


# Resources

- [Static Provisioning](https://github.com/kubernetes-sigs/aws-efs-csi-driver/blob/master/examples/kubernetes/static_provisioning/README.md)
- [Dynamic Provisioning](https://github.com/kubernetes-sigs/aws-efs-csi-driver/blob/master/examples/kubernetes/dynamic_provisioning/README.md)

