terraform {
  backend "s3" {
  }
}

provider "aws" {}

data "aws_region" "current" {}

#temp; we expect the vpc to be created externally
module "vpc" {
    source = "git::https://git.ellucian.com/scm/ar/terraform-module-standard-vpc.git?ref=0.1.0"
    #source = "/Users/sriddell/working/titan/terraform-module-standard-vpc"
    aws_region = "${data.aws_region.current.name}"
    service = "${var.service}"
    environment = "${var.environment}"
    costcenter = "${var.costcenter}"
    poc = "${var.poc}"
    key_name = "sriddell"
    az = "us-east-1d,us-east-1e"
    enable_bastion = "0"
}

module "cluster" {
    source = "git::https://sriddell@git.ellucian.com/scm/~sriddell/terraform-module-ecs-cluster.git?ref=shane"
    vpc_cidr_block = "${module.vpc.vpc_cidr_block}"
    environment = "${var.environment_type}"
    costcenter = "${var.costcenter}"
    poc = "${var.poc}"
    product_name = "${var.stage_name}"
    key_name = "${var.key_name}"
    ami_id = "${var.ecs_ami_id}"
    vpc_id = "${module.vpc.vpc_id}"
    private_subnets = "${join(",", module.vpc.private_subnets)}"
    container_instance_sec_group_ids = []
    instance_type = "${var.ecs_instance_type}"
    asg_desired_capacity="${var.ecs_asg_desired_capacity}"
    asg_max_size="${var.ecs_asg_max_size}"
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id       = "${module.vpc.vpc_id}"
  service_name = "com.amazonaws.us-east-1.s3"
}

output "private_subnets" {
    value = "${module.vpc.private_subnets}"
}

output "public_subnets" {
    value = "${module.vpc.public_subnets}"
}

output "vpc_id" {
    value = "${module.vpc.vpc_id}"
}

output "vpc_cidr_block" {
    value = "${module.vpc.vpc_cidr_block}"
}

# # DB Subnet group to put in RDS database in Gizmo VPC
# resource "aws_db_subnet_group" "clair" {
#   name        = "clair-db-subnet"
#   subnet_ids  = ["${module.vpc.private_subnets}"]

#   tags {
#     Name        = "clair-db-subnet"
#     Environment = "${var.environment}"
#     Service     = "${var.service}"
#     CostCenter  = "${var.costcenter}"
#     POC         = "${var.poc}"
#   }
# }

# resource "aws_security_group" "clair-db-users" {
#     name = "clair-db-users"
#     vpc_id      = "${module.vpc.vpc_id}"
#     tags {
#         Name        = "clair-db-subnet"
#         Environment = "${var.environment}"
#         Service     = "${var.service}"
#         CostCenter  = "${var.costcenter}"
#         POC         = "${var.poc}"
#     }
# }

# resource "aws_security_group" "clair-out" {
#     name = "clair-out"
#     vpc_id      = "${module.vpc.vpc_id}"
#     egress {
#         from_port       = 0
#         to_port         = 0
#         protocol        = "-1"
#         cidr_blocks     = ["0.0.0.0/0"]
#       }

#     tags {
#         Name        = "clair-db-subnet"
#         Environment = "${var.environment}"
#         Service     = "${var.service}"
#         CostCenter  = "${var.costcenter}"
#         POC         = "${var.poc}"
#     }
# }

# # Create a security group for RDS acccess
# resource "aws_security_group" "allow" {
#   name        = "allow_clair_db"
#   description = "Allow all inbound traffic from gizmo ECS tasks"
#   vpc_id      = "${module.vpc.vpc_id}"

#   ingress {
#     from_port   = 0
#     to_port     = 0
#     protocol    = "-1"
#     security_groups = ["${aws_security_group.clair-db-users.id}"]
#   }
# }


# resource "random_string" "postgres_password" {
#   length = 16
#   special = true
# }

# # Postgres RDS database
# resource "aws_db_instance" "default" {
#   identifier           = "clair-db"
#   allocated_storage    = 10
#   storage_type         = "gp2"
#   engine               = "postgres"
#   engine_version       = "10.4"
#   instance_class       = "db.t2.small"
#   name                 = "ClairDb"
#   username             = "postgres"
#   password             = "${random_string.postgres_password.result}"
#   db_subnet_group_name = "${aws_db_subnet_group.clair.name}"
#   skip_final_snapshot  = true
#   vpc_security_group_ids = ["${aws_security_group.allow.id}"]

#   tags {
#     Name        = "${var.service}-clair-db"
#     Environment = "${var.environment}"
#     Service     = "${var.service}"
#     CostCenter  = "${var.costcenter}"
#     POC         = "${var.poc}"
#   }
# }

# data "template_file" "clair-config" {
#     template = "${file("config.yaml")}"
#     vars {
#         host = "${aws_db_instance.default.address}"
#         dbname = "${aws_db_instance.default.name}"
#         user = "postgres"
#         password = "${random_string.postgres_password.result}"
#     }
# }

# resource "aws_ssm_parameter" "clair-db-connect-string" {
#   name        = "/${var.service}/clair-config.yaml"
#   description = "The database connection string for the Clair DB"
#   type        = "SecureString"
#   value       = "${data.template_file.clair-config.rendered}"

#   tags {
#     Name        = "clair-db-connect-string"
#     Environment = "${var.environment}"
#     Service     = "${var.service}"
#     CostCenter  = "${var.costcenter}"
#     POC         = "${var.poc}"
#   }
# }


# data "aws_iam_policy_document" "clair" {

#   # Can fetch secrets
#   statement {
#     actions = ["ssm:GetParameter"]

#     resources = [
#       "${aws_ssm_parameter.clair-db-connect-string.arn}"
#     ]

#     effect = "Allow"
#   }
# }

# resource "aws_iam_policy" "clair" {
#   name   = "clair-db"
#   policy = "${data.aws_iam_policy_document.clair.json}"
# }

# resource "aws_iam_role" "clair" {
#   name = "clair"

#   assume_role_policy = <<EOF
# {
#     "Version": "2008-10-17",
#     "Statement": [
#         {
#             "Action": "sts:AssumeRole",
#             "Effect": "Allow",
#             "Principal": {
#                 "Service": "ec2.amazonaws.com"
#             }
#         }
#     ]
# }
# EOF
# }

# # Attach the policy to the role
# resource "aws_iam_role_policy_attachment" "clair-policy" {
#   role       = "${aws_iam_role.clair.name}"
#   policy_arn = "${aws_iam_policy.clair.arn}"
# }

# resource "aws_iam_instance_profile" "clair" {
#     name = "clair"
#     role = "${aws_iam_role.clair.name}"
# }

# data "template_file" "userdata" {
#     template = "${file("cloudinit.template")}"
# }

# resource "aws_instance" "clair" {
#     count = "1"
#     depends_on= ["aws_iam_instance_profile.clair", "aws_iam_role_policy_attachment.clair-policy", "aws_ssm_parameter.clair-db-connect-string", "aws_db_instance.default"]
#     ami = "ami-0ff8a91507f77f867"
#     instance_type = "t2.small"
#     vpc_security_group_ids = ["${aws_security_group.clair-db-users.id}", "${aws_security_group.clair-out.id}"]
#     subnet_id = "${element(module.vpc.public_subnets,0)}"
#     associate_public_ip_address = true
#     tags {
#         Name        = "Clair"
#         Environment = "${var.environment}"
#         Service     = "${var.service}"
#         CostCenter  = "${var.costcenter}"
#         POC         = "${var.poc}"
#       }
#     key_name="sriddell"
#     iam_instance_profile = "${aws_iam_instance_profile.clair.name}"
#     user_data = "${data.template_file.userdata.rendered}"
# }