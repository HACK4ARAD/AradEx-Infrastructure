# State în S3 cu lock nativ (fără DynamoDB). Bucket-ul îl creează terraform/bootstrap (o singură dată).
# Credențialele vin din mediu (AWS_PROFILE=aws-toolkit), nu din cod.
terraform {
  backend "s3" {
    bucket       = "aradex-tfstate-712710404828"
    key          = "aradex/terraform.tfstate"
    region       = "eu-north-1"
    encrypt      = true
    use_lockfile = true
  }
}
