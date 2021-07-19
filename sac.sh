while read assign; do
 export "$assign";
done < <(sed -nE 's/([a-z_]+): (.*)/\1=\2/ p' sac-parameters.yaml)


accountid=$(aws sts get-caller-identity --query Account --output text)

eni_array=($(echo $enis | tr "," "\n"))

aws s3 mb s3://$accountid-$aws_stackname-cft
aws s3 cp . s3://$accountid-$aws_stackname-cft --recursive

aws cloudformation create-stack --stack-name $aws_stackname-supermaster --template-url https://$accountid-$aws_stackname-cft.s3.amazonaws.com/supermaster.yaml --capabilities CAPABILITY_NAMED_IAM --parameters ParameterKey=DockerHubUserName,ParameterValue=$dockerhub_username ParameterKey=DockerHubToken,ParameterValue=$dockerhub_token ParameterKey=ENI,ParameterValue=${eni_array[0]} ParameterKey=NlbVpcId,ParameterValue=$nlb_vpc ParameterKey=NlbSubnetId,ParameterValue=$nlb_subnets ParameterKey=PermissionsBoundary,ParameterValue=$permission_boundary ParameterKey=AMIId,ParameterValue=$ami_id ParameterKey=InstanceType,ParameterValue=$instance_type

aws cloudformation wait stack-create-complete --stack-name $aws_stackname-supermaster

targetGroupArn=$(aws cloudformation describe-stacks --stack-name $aws_stackname-supermaster --query 'Stacks[].Outputs[?OutputKey==`TargetGroupArn`].OutputValue' --output text)
supermasterIp=$(aws cloudformation describe-stacks --stack-name $aws_stackname-supermaster --query 'Stacks[].Outputs[?OutputKey==`SuperMasterIp`].OutputValue' --output text)
echo "Supermaster is up... Waiting for it to connect to Master's NLB"
aws elbv2 wait target-in-service --target-group-arn $targetGroupArn --targets Id=$supermasterIp,Port=6443

masters=$master_nodes
count=0

while (( masters > ++count )); do   
  echo $count
  aws cloudformation create-stack --stack-name $aws_stackname-master-$count --template-url https://$accountid-$aws_stackname-cft.s3.amazonaws.com/master.yaml --capabilities CAPABILITY_NAMED_IAM --parameters ParameterKey=DockerHubUserName,ParameterValue=$dockerhub_username ParameterKey=DockerHubToken,ParameterValue=$dockerhub_token ParameterKey=ENI,ParameterValue=${eni_array[$count]} ParameterKey=SuperMasterStackName,ParameterValue=$aws_stackname-supermaster ParameterKey=PermissionsBoundary,ParameterValue=$permission_boundary ParameterKey=AMIId,ParameterValue=$ami_id ParameterKey=InstanceType,ParameterValue=$instance_type

  aws cloudformation wait stack-create-complete --stack-name $aws_stackname-master-$count
  echo "Master $count is up... Waiting for it to connect to Master's NLB"
  targetGroupArn=$(aws cloudformation describe-stacks --stack-name $aws_stackname-supermaster --query 'Stacks[].Outputs[?OutputKey==`TargetGroupArn`].OutputValue' --output text)
  masterIp=$(aws cloudformation describe-stacks --stack-name $aws_stackname-master-$count --query 'Stacks[].Outputs[?OutputKey==`MasterIp`].OutputValue' --output text)

  aws elbv2 wait target-in-service --target-group-arn $targetGroupArn --targets Id=$masterIp,Port=6443
done

workers=$worker_nodes
count=0
subnets=$(echo $nlb_subnets | sed 's/\\//g')
subnet_array=($(echo $subnets | tr "," "\n"))


while (( workers >= ++count )); do   
  echo $count
  worker_subnet=${subnet_array[RANDOM%${#subnet_array[@]}]}
  aws cloudformation create-stack --stack-name $aws_stackname-worker-$count --template-url https://$accountid-$aws_stackname-cft.s3.amazonaws.com/worker.yaml --capabilities CAPABILITY_NAMED_IAM --parameters ParameterKey=DockerHubUserName,ParameterValue=$dockerhub_username ParameterKey=DockerHubToken,ParameterValue=$dockerhub_token ParameterKey=SubnetId,ParameterValue=$worker_subnet ParameterKey=SecurityGroupIds,ParameterValue=$security_groups ParameterKey=SuperMasterStackName,ParameterValue=$aws_stackname-supermaster ParameterKey=PermissionsBoundary,ParameterValue=$permission_boundary ParameterKey=AMIId,ParameterValue=$ami_id ParameterKey=InstanceType,ParameterValue=$instance_type

  aws cloudformation wait stack-create-complete --stack-name $aws_stackname-worker-$count
  echo "Worker $count is up..."
 
done

aws s3 cp s3://$accountid-$aws_stackname-supermaster . --recursive
chmod 400 $aws_stackname-supermaster.pem 

curl -LO https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl
chmod +x kubectl
sudo mv kubectl /usr/bin
mkdir $HOME/.kube

scp -o StrictHostKeyChecking=no -i $aws_stackname-supermaster.pem ec2-user@$supermasterIp:$HOME/.kube/config $HOME/.kube/config

kubectl get nodes
kubectl apply -f deploy-dashboard/deploy-dashboard.yaml
NodePort=$(kubectl get svc kubernetes-dashboard --namespace kubernetes-dashboard -o=jsonpath='{.spec.ports[?(@.port==443)].nodePort}')
NodeIP=$(kubectl get node -o=jsonpath='{.items[?(@.metadata.labels.supermaster=="yes")].status.addresses[?(@.type=="InternalIP")].address}')
kubectl apply -f deploy-dashboard/admin-user.yaml

echo https://$NodeIP:$NodePort

dashboardtoken=$(kubectl -n kube-system describe secret $(kubectl -n kube-system get secret | grep clusteradmin | awk '{print $1}') | grep token:)
aws secretsmanager create-secret --name $aws_stackname-dashboardtoken --description "token to join login to dashboard" --secret-string "$dashboardtoken" --region us-east-1
aws cloudformation create-stack --stack-name $aws_stackname-dashboard-alb --template-url https://$accountid-$aws_stackname-cft.s3.amazonaws.com/deploy-dashboard/dashboard-alb.yaml --capabilities CAPABILITY_NAMED_IAM --parameters ParameterKey=AlbVpcId,ParameterValue=$nlb_vpc ParameterKey=AlbSubnetId,ParameterValue=$nlb_subnets ParameterKey=AlbSecurityGroups,ParameterValue=$security_groups ParameterKey=DashboardNodePort,ParameterValue=$NodePort ParameterKey=AlbCertificateArn,ParameterValue=$dashboard_certificate_arn
aws cloudformation wait stack-create-complete --stack-name $aws_stackname-dashboard-alb
SuperMasterId=$(aws cloudformation describe-stacks --stack-name $aws_stackname-supermaster --query 'Stacks[].Outputs[?OutputKey==`SuperMasterId`].OutputValue' --output text)
targetGroupArn=$(aws cloudformation describe-stacks --stack-name $aws_stackname-dashboard-alb --query 'Stacks[].Outputs[?OutputKey==`TargetGroupArn`].OutputValue' --output text)
aws elbv2 register-targets --target-group-arn ${TargetGroupArn} --targets Id=$SuperMasterId,Port=$NodePort --region us-east-1

aws s3 rm s3://$accountid-$aws_stackname-cft --recursive
aws s3 rb s3://$accountid-$aws_stackname-cft
rm -rf $HOME/.kube
rm $aws_stackname-supermaster.pem
