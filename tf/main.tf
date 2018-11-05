terraform {
  backend "s3" {
  }
}

provider "aws" {
    version = "~> 1.40"
}
provider "null" {
    version = "~> 1.0"
}

provider "template" {
    version = "~> 1.0"
}

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
    environment = "${var.environment}"
    costcenter = "${var.costcenter}"
    poc = "${var.poc}"
    product_name = "EllucianClair"
    key_name = "${var.key_name}"
    ami_id = "${var.ecs_ami_id}"
    vpc_id = "${module.vpc.vpc_id}"
    private_subnets = "${join(",", module.vpc.private_subnets)}"
    container_instance_sec_group_ids = []
    instance_type = "t3.medium"
    asg_desired_capacity="1"
    asg_max_size="1"
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

resource "aws_sqs_queue" "queue" {
  name                      = "ellucian-clair-index-requests"
  delay_seconds             = 0
  message_retention_seconds = 1209600
  #redrive_policy            = "{\"deadLetterTargetArn\":\"${aws_sqs_queue.terraform_queue_deadletter.arn}\",\"maxReceiveCount\":4}"

  tags {
    Name        = "clair-db-subnet"
    Environment = "${var.environment}"
    Service     = "${var.service}"
    CostCenter  = "${var.costcenter}"
    POC         = "${var.poc}"
  }
}

resource "aws_s3_bucket" "bucket" {
  bucket = "clair-scan-results"
  acl    = "private"

  tags {
    Environment = "${var.environment}"
    Service     = "${var.service}"
    CostCenter  = "${var.costcenter}"
    POC         = "${var.poc}"
  }
}


# DB Subnet group to put in RDS database in Gizmo VPC
resource "aws_db_subnet_group" "clair" {
  name        = "clair-db-subnet"
  subnet_ids  = ["${module.vpc.private_subnets}"]

  tags {
    Name        = "clair-db-subnet"
    Environment = "${var.environment}"
    Service     = "${var.service}"
    CostCenter  = "${var.costcenter}"
    POC         = "${var.poc}"
  }
}

resource "aws_security_group" "clair-db-users" {
    name = "clair-db-users"
    vpc_id      = "${module.vpc.vpc_id}"
    egress {
        from_port       = 0
        to_port         = 0
        protocol        = "-1"
        cidr_blocks     = ["0.0.0.0/0"]
    }
    tags {
        Environment = "${var.environment}"
        Service     = "${var.service}"
        CostCenter  = "${var.costcenter}"
        POC         = "${var.poc}"
    }
}

# Create a security group for RDS acccess
resource "aws_security_group" "allow" {
  name        = "allow_clair_db"
  description = "Allow all inbound traffic from db processes"
  vpc_id      = "${module.vpc.vpc_id}"

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    security_groups = ["${aws_security_group.clair-db-users.id}"]
  }
}


resource "random_string" "postgres_password" {
  length = 16
  special = false
}

# Postgres RDS database
resource "aws_db_instance" "default" {
  identifier           = "clair-db"
  allocated_storage    = 10
  storage_type         = "gp2"
  engine               = "postgres"
  engine_version       = "10.4"
  instance_class       = "db.t2.small"
  name                 = "ClairDb"
  username             = "postgres"
  password             = "${random_string.postgres_password.result}"
  db_subnet_group_name = "${aws_db_subnet_group.clair.name}"
  skip_final_snapshot  = true
  vpc_security_group_ids = ["${aws_security_group.allow.id}"]

  tags {
    Name        = "${var.service}-clair-db"
    Environment = "${var.environment}"
    Service     = "${var.service}"
    CostCenter  = "${var.costcenter}"
    POC         = "${var.poc}"
  }
}

data "template_file" "clair-config" {
    template = "${file("config.yaml")}"
    vars {
        host = "${aws_db_instance.default.address}"
        dbname = "${aws_db_instance.default.name}"
        user = "postgres"
        password = "${random_string.postgres_password.result}"
    }
}


resource "aws_ssm_parameter" "clair-db-connect-string" {
  name        = "/${var.service}/clair-config.yaml"
  description = "The database connection string for the Clair DB"
  type        = "SecureString"
  value       = "${base64encode(data.template_file.clair-config.rendered)}"

  tags {
    Name        = "clair-db-connect-string"
    Environment = "${var.environment}"
    Service     = "${var.service}"
    CostCenter  = "${var.costcenter}"
    POC         = "${var.poc}"
  }
}


data "aws_iam_policy_document" "clair" {

  # Can fetch secrets
  statement {
    actions = ["ssm:GetParameter"]

    resources = [
      "${aws_ssm_parameter.clair-db-connect-string.arn}"
    ]

    effect = "Allow"
  }

  statement {
    actions = [
        "ecr:GetAuthorizationToken",
        "ecr:BatchCheckLayerAvailability",
        "ecr:GetDownloadUrlForLayer",
        "ecr:GetRepositoryPolicy",
        "ecr:DescribeRepositories",
        "ecr:ListImages",
        "ecr:DescribeImages",
        "ecr:BatchGetImage"
    ]
    resources = ["*"]
    effect = "Allow"
  }
}

resource "aws_iam_policy" "clair" {
  name   = "clair"
  policy = "${data.aws_iam_policy_document.clair.json}"
}

resource "aws_iam_role" "clair" {
  name = "clair"

  assume_role_policy = <<EOF
{
    "Version": "2008-10-17",
    "Statement": [
        {
            "Action": "sts:AssumeRole",
            "Effect": "Allow",
            "Principal": {
                "Service": "ecs-tasks.amazonaws.com"
            }
        }
    ]
}
EOF
}

# Attach the policy to the role
resource "aws_iam_role_policy_attachment" "clair" {
  role       = "${aws_iam_role.clair.name}"
  policy_arn = "${aws_iam_policy.clair.arn}"
}


data "aws_iam_policy_document" "clair-scanner" {

  # Can fetch secrets
  statement {
    actions = ["s3:*"]

    resources = [
      "${aws_s3_bucket.bucket.arn}",
      "${aws_s3_bucket.bucket.arn}/*"
    ]

    effect = "Allow"
  }
  statement {
    actions = ["sqs:*"]

    resources = [
      "${aws_sqs_queue.queue.arn}",
      "${aws_sqs_queue.queue.arn}/*"
    ]

    effect = "Allow"
  }
  statement {
    actions = [
        "ecr:GetAuthorizationToken",
        "ecr:BatchCheckLayerAvailability",
        "ecr:GetDownloadUrlForLayer",
        "ecr:GetRepositoryPolicy",
        "ecr:DescribeRepositories",
        "ecr:ListImages",
        "ecr:DescribeImages",
        "ecr:BatchGetImage"
    ]
    resources = ["*"]
    effect = "Allow"
  }
}

resource "aws_iam_policy" "clair-scanner" {
  name   = "clair-scanner"
  policy = "${data.aws_iam_policy_document.clair-scanner.json}"
}

resource "aws_iam_role" "clair-scanner" {
  name = "clair-scanner"

  assume_role_policy = <<EOF
{
    "Version": "2008-10-17",
    "Statement": [
        {
            "Action": "sts:AssumeRole",
            "Effect": "Allow",
            "Principal": {
                "Service": "ecs-tasks.amazonaws.com"
            }
        }
    ]
}
EOF
}

# Attach the policy to the role
resource "aws_iam_role_policy_attachment" "clair-scanner" {
  role       = "${aws_iam_role.clair-scanner.name}"
  policy_arn = "${aws_iam_policy.clair-scanner.arn}"
}

resource "aws_cloudwatch_log_group" "ecs" {
  name = "ellucian-clair"

  tags {
    Environment = "${var.environment}"
    Service     = "${var.service}"
    CostCenter  = "${var.costcenter}"
    POC         = "${var.poc}"
  }
}


data "template_file" "clair_task" {
    template = "${file("clair.json")}"
    vars {
        config_parameter_name = "/${var.service}/clair-config.yaml"
        log_group = "${aws_cloudwatch_log_group.ecs.name}"
        region = "${data.aws_region.current.name}"
    }
}

resource "aws_ecs_task_definition" "clair" {
    family = "ellucian-clair"
    network_mode = "awsvpc"
    container_definitions = "${data.template_file.clair_task.rendered}"
    task_role_arn = "${aws_iam_role.clair.arn}"
}

resource "aws_lb_target_group" "clair" {
  name     = "clair"
  port     = 6060
  protocol = "HTTP"
  vpc_id   = "${module.vpc.vpc_id}"
  target_type = "ip"
}


resource "aws_security_group" "clair-users" {
    name = "clair-users"
    vpc_id      = "${module.vpc.vpc_id}"
    egress {
        from_port       = 0
        to_port         = 0
        protocol        = "-1"
        cidr_blocks     = ["0.0.0.0/0"]
    }
    tags {
        Environment = "${var.environment}"
        Service     = "${var.service}"
        CostCenter  = "${var.costcenter}"
        POC         = "${var.poc}"
    }
}

resource "aws_security_group" "allow-clair-access" {
  name        = "allow_clair_access"
  description = "Allow all inbound traffic from db processes"
  vpc_id      = "${module.vpc.vpc_id}"

  ingress {
    from_port   = 6060
    to_port     = 6060
    protocol    = "tcp"
    security_groups = ["${aws_security_group.clair-users.id}"]
  }
}

resource "aws_lb" "clair" {
  name               = "clair"
  internal           = true
  load_balancer_type = "application"
  security_groups    = ["${aws_security_group.allow-clair-access.id}"]
  subnets            = ["${module.vpc.private_subnets}"]

  tags {
    Name        = "clair-db-subnet"
    Environment = "${var.environment}"
    Service     = "${var.service}"
    CostCenter  = "${var.costcenter}"
    POC         = "${var.poc}"
  }
}



resource "aws_lb_listener" "clair" {
  depends_on = ["aws_lb.clair"]
  load_balancer_arn = "${aws_lb.clair.arn}"
  port              = "6060"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = "${aws_lb_target_group.clair.arn}"
  }
}

resource "aws_ecs_service" "clair" {
  depends_on = ["aws_lb_target_group.clair", "aws_lb.clair", "aws_lb_listener.clair"]
  name            = "clair"
  cluster         = "${module.cluster.cluster_id}"
  task_definition = "${aws_ecs_task_definition.clair.arn}"
  desired_count   = 1
  network_configuration {
    subnets = ["${module.vpc.private_subnets}"]
    security_groups = ["${aws_security_group.clair-db-users.id}"]
  }

  load_balancer {
    target_group_arn = "${aws_lb_target_group.clair.arn}"
    container_name   = "clair"
    container_port   = 6060
  }

}


data "template_file" "clair-scanner" {
    template = "${file("clair-scanner.json")}"
    vars {
        clair_endpoint = "${aws_lb.clair.dns_name}:6060"
        sqs_url = "${aws_sqs_queue.queue.id}"
        log_group = "${aws_cloudwatch_log_group.ecs.name}"
        region = "${data.aws_region.current.name}"
    }
}


resource "aws_ecs_task_definition" "clair-scanner" {
    family = "ellucian-clair-scanner"
    network_mode = "awsvpc"
    container_definitions = "${data.template_file.clair-scanner.rendered}"
    task_role_arn = "${aws_iam_role.clair-scanner.arn}"
}


resource "aws_ecs_service" "clair-scanner" {
  name            = "clair-scanner"
  cluster         = "${module.cluster.cluster_id}"
  task_definition = "${aws_ecs_task_definition.clair-scanner.arn}"
  desired_count   = 1
  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent = 100
  network_configuration {
    subnets = ["${module.vpc.private_subnets}"]
    security_groups = ["${aws_security_group.clair-users.id}"]
  }

}
