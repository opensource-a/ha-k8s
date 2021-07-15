kubectl apply -f deploy-dashboard.yaml
NodePort=$(kubectl get svc kubernetes-dashboard --namespace kubernetes-dashboard -o=jsonpath='{.spec.ports[?(@.port==443)].nodePort}')
NodeIP=$(kubectl get node -o=jsonpath='{.items[?(@.metadata.labels.supermaster=="yes")].status.addresses[?(@.type=="InternalIP")].address}')
kubectl apply -f admin-user.yaml

echo https://$NodeIP:$NodePort

kubectl -n kube-system describe secret $(kubectl -n kube-system get secret | grep clusteradmin | awk '{print $1}') | grep token:
