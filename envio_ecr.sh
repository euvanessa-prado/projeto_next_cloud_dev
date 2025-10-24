ECR_REGISTRY="448522291635.dkr.ecr.us-east-1.amazonaws.com"
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin $ECR_REGISTRY
docker build -t next-cloud .
docker tag next-cloud:latest 448522291635.dkr.ecr.us-east-1.amazonaws.com/next-cloud:latest
docker push $ECR_REGISTRY/next-cloud:latest