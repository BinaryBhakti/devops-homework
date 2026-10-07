# Fix: storage that is really shared by every replica

See [Task 3 of the homework README](../../README.md#the-bug-persistent-data-that-depends-on-which-node-the-pod-lands-on).

`pvc-csi.yaml` is the course's `web-data` claim with `storageClassName: csi-hostpath-sc` (Minikube's
`csi-hostpath-driver` addon). The Deployment is switched to it with:

```bash
minikube addons enable volumesnapshots
minikube addons enable csi-hostpath-driver
kubectl apply -f pvc-csi.yaml
kubectl -n production-webapp patch deploy web-app --type=json \
  -p='[{"op":"replace","path":"/spec/template/spec/volumes/0/persistentVolumeClaim/claimName","value":"web-data-csi"}]'
```
