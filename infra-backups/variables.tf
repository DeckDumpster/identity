variable "aws_region" {
  type    = string
  default = "us-west-2"
}

variable "deploy_role_arn" {
  type        = string
  description = "DeployRoleArn output of TerraformBootstrap (role terraform-deploy) in the CI account."
}

variable "permissions_boundary_arn" {
  type        = string
  description = "Boundary the terraform-deploy role requires on every IAM user or role it creates."
  default     = "arn:aws:iam::189923011121:policy/terraform-deploy-boundary"
}
