terraform {

  required_version = "~> 1.14"

  required_providers {

    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }

  }
}

## Region and credentials come from the environment, so this fixture carries no
## account, profile or role of its own and can be pointed at any scratch
## account.
provider "aws" {}
