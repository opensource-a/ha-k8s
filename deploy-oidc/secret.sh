kubectl create namespace ingress-nginx
kubectl create secret docker-registry regcred --namespace ingress-nginx --docker-server=docker.io --docker-username=${DockerHubUserName} --docker-password=${DockerHubToken} 
              
