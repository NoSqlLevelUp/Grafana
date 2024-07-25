terraform {
  backend "s3"{
  bucket = "grafana-state-bucket-no-sql"
  key = "terraform.tfstate"
  region = "eu-west-1"
  }
}