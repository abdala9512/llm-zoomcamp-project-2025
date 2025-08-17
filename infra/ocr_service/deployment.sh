terraform init
terraform plan
terraform apply -target=aws_s3_bucket.in -target=aws_s3_bucket.out -target=aws_ecr_repository.repo

ECR_URI="$(terraform -chdir=../../infra/ocr_service output -raw ecr_repo_url)"
AWS_REGION="$(terraform -chdir=../../infra/ocr_service output -raw input_bucket >/dev/null 2>&1; echo us-east-1)"

aws ecr get-login-password --region "$AWS_REGION" \
| docker login --username AWS --password-stdin "${ECR_URI%/*}"

cd ../../services/ocr_service

docker build -t "${ECR_URI}:latest" .
docker push "${ECR_URI}:latest"

# Apply with the function image tag
cd ../../infra/ocr_service
terraform apply -var="image_tag=latest"
