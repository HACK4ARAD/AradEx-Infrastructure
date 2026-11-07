terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      # aws.us_east_1 rămâne declarat: Terraform are nevoie de el ca să șteargă certificatul vechi pentru CloudFront
      # (creat în us-east-1 înainte de trecerea la ALB). Nicio resursă nouă nu-l mai folosește.
      configuration_aliases = [aws.us_east_1]
    }
  }
}
