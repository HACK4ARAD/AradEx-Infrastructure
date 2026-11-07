provider "aws" {
  region              = "eu-north-1"
  allowed_account_ids = ["712710404828"]

  default_tags {
    tags = { Project = "AradExperience" }
  }
}

# Certificatul pentru CloudFront trebuie să fie în us-east-1.
provider "aws" {
  alias               = "us_east_1"
  region              = "us-east-1"
  allowed_account_ids = ["712710404828"]

  default_tags {
    tags = { Project = "AradExperience" }
  }
}
