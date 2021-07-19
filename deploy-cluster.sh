aws_stackname=k8s-sac-101
dockerhub_username=
dockerhub_token=
enis=eni-0c0f71f0cbd0f35a8,eni2,eni3,eni4,eni5
master_nodes=5
worker_nodes=4
nlb_vpc=vpc-97ceceed
nlb_subnets=subnet-1b15e17d,subnet-df3b00e1,subnet-fda454a2,subnet-36f80a17,subnet-97e463da,subnet-ce05abc0
permission_boundary=arn:aws:iam::aws:policy/AdministratorAccess
ami_id=ami-0742b4e673072066f
instance_type=t2.medium

accountid=$(aws sts get-caller-identity --query Account --output text)

eni_array=($(echo $enis | tr "," "\n"))

aws s3 mb s3://$accountid-$aws_stackname-cft
aws s3 cp . s3://$accountid-$aws_stackname-cft --recursive

aws cloudformation create-stack --stack-name $aws_stackname-supermaster --template-url https://$accountid-$aws_stackname-cft.s3.amazonaws.com/supermaster.yaml --capabilities CAPABILITY_NAMED_IAM --parameters ParameterKey= DockerHubUserName,ParameterValue=$dockerhub_username ParameterKey= DockerHubToken,ParameterValue=$dockerhub_token ParameterKey=ENI,ParameterValue=${eni_array[0]} ParameterKey=NlbVpcId,ParameterValue=$nlb_vpc ParameterKey=NlbSubnetId,ParameterValue=$nlb_subnets ParameterKey=PermissionsBoundary,ParameterValue=$permission_boundary ParameterKey=AMIId,ParameterValue=$ami_id ParameterKey=InstanceType,ParameterValue=$instance_type

aws cloudformation wait stack-create-complete --stack-name $aws_stackname-supermaster

targetGroupArn=$(aws cloudformation describe-stacks --stack-name $aws_stackname-supermaster --query Stacks[].Outputs[?OutputKey==TargetGroupArn].OutputValue --output text)
supermasterIp=$(aws cloudformation describe-stacks --stack-name $aws_stackname-supermaster --query Stacks[].Outputs[?OutputKey==SuperMasterIp].OutputValue --output text)

aws elbv2 wait target-in-service --target-group-arn $targetGroupArn --targets Id=$supermasterIp,Port=6443

count=0

while (( masters > ++count )); do   
  aws cloudformation create-stack --stack-name $aws_stackname-master-$count --template-url https://$accountid-$aws_stackname-cft.s3.amazonaws.com/master.yaml --capabilities CAPABILITY_NAMED_IAM --parameters ParameterKey= DockerHubUserName,ParameterValue=$dockerhub_username ParameterKey= DockerHubToken,ParameterValue=$dockerhub_token ParameterKey=ENI,ParameterValue=${eni_array[$count]} ParameterKey=SuperMasterStackName,ParameterValue=$aws_stackname-supermaster ParameterKey=PermissionsBoundary,ParameterValue=$permission_boundary ParameterKey=AMIId,ParameterValue=$ami_id ParameterKey=InstanceType,ParameterValue=$instance_type

  aws cloudformation wait stack-create-complete --stack-name $aws_stackname-master-$count
  targetGroupArn=$(aws cloudformation describe-stacks --stack-name $aws_stackname-supermaster --query Stacks[].Outputs[?OutputKey==TargetGroupArn].OutputValue --output text)
  masterIp=$(aws cloudformation describe-stacks --stack-name $aws_stackname-master-$count --query Stacks[].Outputs[?OutputKey==MasterIp].OutputValue --output text)

  aws elbv2 wait target-in-service --target-group-arn $targetGroupArn --targets Id=$masterIp,Port=6443
done



