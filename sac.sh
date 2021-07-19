while read assign; do
 export "$assign";
done < <(sed -nE 's/([a-z_]+): (.*)/\1=\2/ p' sac-parameters.yml)


accountid=$(aws sts get-caller-identity --query Account --output text)

eni_array=($(echo $enis | tr "," "\n"))

aws s3 mb s3://$accountid-$aws_stackname-cft
aws s3 cp . s3://$accountid-$aws_stackname-cft --recursive

aws cloudformation create-stack --stack-name $aws_stackname-supermaster --template-url https://$accountid-$aws_stackname-cft.s3.amazonaws.com/supermaster.yaml --capabilities CAPABILITY_NAMED_IAM --parameters ParameterKey=DockerHubUserName,ParameterValue=$dockerhub_username ParameterKey=DockerHubToken,ParameterValue=$dockerhub_token ParameterKey=ENI,ParameterValue=${eni_array[0]} ParameterKey=NlbVpcId,ParameterValue=$nlb_vpc ParameterKey=NlbSubnetId,ParameterValue=$nlb_subnets ParameterKey=PermissionsBoundary,ParameterValue=$permission_boundary ParameterKey=AMIId,ParameterValue=$ami_id ParameterKey=InstanceType,ParameterValue=$instance_type

aws cloudformation wait stack-create-complete --stack-name $aws_stackname-supermaster

targetGroupArn=$(aws cloudformation describe-stacks --stack-name $aws_stackname-supermaster --query Stacks[].Outputs[?OutputKey==TargetGroupArn].OutputValue --output text)
supermasterIp=$(aws cloudformation describe-stacks --stack-name $aws_stackname-supermaster --query Stacks[].Outputs[?OutputKey==SuperMasterIp].OutputValue --output text)

aws elbv2 wait target-in-service --target-group-arn $targetGroupArn --targets Id=$supermasterIp,Port=6443

count=0

while (( masters > ++count )); do   
  aws cloudformation create-stack --stack-name $aws_stackname-master-$count --template-url https://$accountid-$aws_stackname-cft.s3.amazonaws.com/master.yaml --capabilities CAPABILITY_NAMED_IAM --parameters ParameterKey=DockerHubUserName,ParameterValue=$dockerhub_username ParameterKey=DockerHubToken,ParameterValue=$dockerhub_token ParameterKey=ENI,ParameterValue=${eni_array[$count]} ParameterKey=SuperMasterStackName,ParameterValue=$aws_stackname-supermaster ParameterKey=PermissionsBoundary,ParameterValue=$permission_boundary ParameterKey=AMIId,ParameterValue=$ami_id ParameterKey=InstanceType,ParameterValue=$instance_type

  aws cloudformation wait stack-create-complete --stack-name $aws_stackname-master-$count
  targetGroupArn=$(aws cloudformation describe-stacks --stack-name $aws_stackname-supermaster --query Stacks[].Outputs[?OutputKey==TargetGroupArn].OutputValue --output text)
  masterIp=$(aws cloudformation describe-stacks --stack-name $aws_stackname-master-$count --query Stacks[].Outputs[?OutputKey==MasterIp].OutputValue --output text)

  aws elbv2 wait target-in-service --target-group-arn $targetGroupArn --targets Id=$masterIp,Port=6443
done



aws s3 rm s3://$accountid-$aws_stackname-cft --recursive
aws s3 rb s3://$accountid-$aws_stackname-cft
