variable "service" {}
variable "environment" {}
variable "costcenter" {}
variable "poc" {}

variable "ecs_ami_id" {}
variable "key_name" {}

variable "number_of_scanners" {default=1}
variable "number_of_ecs_instances" {default=1}

variable "instance_type" {}

variable prefix {}

variable number_of_clair_instances {
    default = 1
}

# variable "private_subnet_ids" {
#   type = "list"
# }

#variable "vpc_id" {}