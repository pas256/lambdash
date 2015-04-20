bucket_name=pas256-lambdash

function=lambdash
lambda_execution_role_name=lambda-$function-execution
lambda_execution_access_policy_name=lambda-$function-execution-access
log_group_name=/aws/lambda/$function
region=us-west-2

lambda_execution_role_arn=$(aws iam create-role   --role-name "$lambda_execution_role_name"   --assume-role-policy-document '{
      "Version": "2012-10-17",
      "Statement": [{
          "Sid": "",
          "Effect": "Allow",
          "Principal": {
            "Service": "lambda.amazonaws.com"
          },
          "Action": "sts:AssumeRole"
      }]
    }'   --output text   --query 'Role.Arn'
)
echo lambda_execution_role_arn=$lambda_execution_role_arn

aws iam put-role-policy   --role-name "$lambda_execution_role_name"   --policy-name "$lambda_execution_access_policy_name"   --policy-document '{
      "Version": "2012-10-17",
      "Statement": [{
          "Effect": "Allow",
          "Action": [ "logs:*" ],
          "Resource": "arn:aws:logs:*:*:*"
      }, {
          "Effect": "Allow",
          "Action": [ "s3:PutObject" ],
          "Resource": "arn:aws:s3:::'$bucket_name'/'$function'/*"
      }]
  }'

wget -q -O$function.js   https://raw.githubusercontent.com/alestic/lambdash/master/lambdash.js

npm install async fs tmp
zip -r $function.zip $function.js node_modules
aws lambda create-function --region $region --function-name "$function"  --runtime nodejs   --handler "$function.handler"   --role "$lambda_execution_role_arn"   --timeout 60   --memory-size 256  --zip-file "fileb://./$function.zip"

aws lambda update-function-code  --region $region  --function-name "$function"   --zip-file "fileb://./$function.zip"

cat > $function-args.json <<EOM
{
    "command": "ls -laiR /",
    "bucket":  "$bucket_name",
    "stdout":  "$function/stdout.txt",
    "stderr":  "$function/stderr.txt"
}
EOM

aws lambda invoke-async   --region $region --function-name "$function"   --invoke-args "$function-args.json"

log_stream_names=$(aws logs describe-log-streams   --log-group-name "$log_group_name"   --output text   --query 'logStreams[*].logStreamName') &&
for log_stream_name in $log_stream_names; do
  aws logs get-log-events     --log-group-name "$log_group_name"     --log-stream-name "$log_stream_name"     --output text     --query 'events[*].message'
done | less

aws s3 mb --region $region s3://$bucket_name
aws s3 cp --region $region s3://$bucket_name/$function/stdout.txt .
aws s3 cp --region $region s3://$bucket_name/$function/stderr.txt .
less stdout.txt stderr.txt

aws s3 rm --region $region s3://$bucket_name/$function/stdout.txt
aws s3 rm --region $region s3://$bucket_name/$function/stderr.txt
#aws lambda delete-function   --function-name "$function"
#aws iam delete-role-policy   --role-name "$lambda_execution_role_name"   --policy-name "$lambda_execution_access_policy_name"
#aws iam delete-role   --role-name "$lambda_execution_role_name"
#aws logs delete-log-group   --log-group-name "$log_group_name"


