terraform {
  backend "s3" {
  }
}

provider "aws" {
  version = "~> 2.19.0"
}

provider "null" {
  version = "~> 2.1.2"
}

provider "template" {
  version = "~> 2.1.2"
}

data "aws_region" "current" {
}

#temp; we expect the vpc to be created externally
module "vpc" {
  source = "git::https://github.com/sriddell/terraform-module-standard-vpc.git?ref=1.0.0"

  #source = "/Users/sriddell/working/titan/terraform-module-standard-vpc"
  aws_region     = data.aws_region.current.name
  service        = var.service
  environment    = var.environment
  costcenter     = var.costcenter
  poc            = var.poc
  key_name       = var.key_name
  az             = "us-east-1d,us-east-1e"
  enable_bastion = "0"
}

module "cluster" {
  source                           = "git::https://github.com/sriddell/terraform-module-ecs-cluster.git?ref=2.0.2"
  vpc_cidr_block                   = module.vpc.vpc_cidr_block
  environment                      = var.environment
  costcenter                       = var.costcenter
  poc                              = var.poc
  cluster_name                     = "${var.environment}-ecr-cve-monitor"
  key_name                         = var.key_name
  ami_id                           = var.ecs_ami_id
  vpc_id                           = module.vpc.vpc_id
  private_subnets                  = join(",", module.vpc.private_subnets)
  container_instance_sec_group_ids = []
  instance_type                    = var.instance_type
  asg_desired_capacity             = var.number_of_ecs_instances
  asg_max_size                     = var.number_of_ecs_instances
  asg_min_size                     = "0"
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id       = module.vpc.vpc_id
  service_name = "com.amazonaws.us-east-1.s3"
}

output "private_subnets" {
  value = module.vpc.private_subnets
}

output "public_subnets" {
  value = module.vpc.public_subnets
}

output "vpc_id" {
  value = module.vpc.vpc_id
}

output "vpc_cidr_block" {
  value = module.vpc.vpc_cidr_block
}

resource "aws_sqs_queue" "dead_letter" {
  name                      = "${var.prefix}-clair-dead-letter"
  delay_seconds             = 0
  message_retention_seconds = 1209600
  tags = {
    Environment = var.environment
    Service     = var.service
    CostCenter  = var.costcenter
    POC         = var.poc
  }
}

resource "aws_sqs_queue" "queue" {
  name                      = "${var.prefix}-clair-index-requests"
  delay_seconds             = 0
  message_retention_seconds = 1209600
  redrive_policy            = "{\"deadLetterTargetArn\":\"${aws_sqs_queue.dead_letter.arn}\",\"maxReceiveCount\":4}"

  tags = {
    Environment = var.environment
    Service     = var.service
    CostCenter  = var.costcenter
    POC         = var.poc
  }
}

output "input_queue" {
  value = aws_sqs_queue.queue.id
}

resource "aws_s3_bucket" "bucket" {
  bucket = "${var.prefix}-clair-scan-results"
  acl    = "private"

  tags = {
    Environment = var.environment
    Service     = var.service
    CostCenter  = var.costcenter
    POC         = var.poc
  }
}

output "report_bucket" {
  value = aws_s3_bucket.bucket.id
}

# DB Subnet group to put in RDS database in vpc
resource "aws_db_subnet_group" "clair" {
  name = "clair-db-subnet"
  # TF-UPGRADE-TODO: In Terraform v0.10 and earlier, it was sometimes necessary to
  # force an interpolation expression to be interpreted as a list by wrapping it
  # in an extra set of list brackets. That form was supported for compatibilty in
  # v0.11, but is no longer supported in Terraform v0.12.
  #
  # If the expression in the following list itself returns a list, remove the
  # brackets to avoid interpretation as a list of lists. If the expression
  # returns a single list item then leave it as-is and remove this TODO comment.
  subnet_ids = "${module.vpc.private_subnets}"

  tags = {
    Name        = "clair-db-subnet"
    Environment = var.environment
    Service     = var.service
    CostCenter  = var.costcenter
    POC         = var.poc
  }
}

#Create a security group for RDS acccess
resource "aws_security_group" "allow-db" {
  name        = "allow_clair_db"
  description = "Allow all inbound traffic from db processes"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port = 5432
    to_port   = 5432
    protocol  = "tcp"
    # TF-UPGRADE-TODO: In Terraform v0.10 and earlier, it was sometimes necessary to
    # force an interpolation expression to be interpreted as a list by wrapping it
    # in an extra set of list brackets. That form was supported for compatibilty in
    # v0.11, but is no longer supported in Terraform v0.12.
    #
    # If the expression in the following list itself returns a list, remove the
    # brackets to avoid interpretation as a list of lists. If the expression
    # returns a single list item then leave it as-is and remove this TODO comment.
    cidr_blocks = [module.vpc.vpc_cidr_block]
  }
}

resource "random_string" "postgres_password" {
  length  = 16
  special = false
}

# Postgres RDS database
resource "aws_db_instance" "default" {
  identifier             = "clair-db"
  allocated_storage      = 10
  storage_type           = "gp2"
  engine                 = "postgres"
  engine_version         = "10.6"
  instance_class         = "db.t2.small"
  name                   = "ClairDb"
  username               = "postgres"
  password               = random_string.postgres_password.result
  db_subnet_group_name   = aws_db_subnet_group.clair.name
  skip_final_snapshot    = true
  vpc_security_group_ids = [aws_security_group.allow-db.id]

  tags = {
    Name        = "${var.service}-clair-db"
    Environment = var.environment
    Service     = var.service
    CostCenter  = var.costcenter
    POC         = var.poc
  }
}

resource "aws_dynamodb_table" "indexed-layers" {
  name           = "clair-indexed-layers"
  billing_mode   = "PAY_PER_REQUEST"
  read_capacity  = 2
  write_capacity = 100
  hash_key       = "layer_name"
  range_key      = "image_name"

  attribute {
    name = "layer_name"
    type = "S"
  }
  attribute {
    name = "image_name"
    type = "S"
  }

  tags = {
    Name        = "${var.service}-clair-db"
    Environment = var.environment
    Service     = var.service
    CostCenter  = var.costcenter
    POC         = var.poc
  }
}

data "template_file" "clair-config" {
  template = file("config.yaml")
  vars = {
    host     = aws_db_instance.default.address
    dbname   = aws_db_instance.default.name
    user     = "postgres"
    password = random_string.postgres_password.result
  }
}

resource "aws_ssm_parameter" "clair-db-connect-string" {
  name        = "/${var.service}/clair-config.yaml"
  description = "The database connection string for the Clair DB"
  type        = "SecureString"
  value       = base64encode(data.template_file.clair-config.rendered)

  tags = {
    Name        = "clair-db-connect-string"
    Environment = var.environment
    Service     = var.service
    CostCenter  = var.costcenter
    POC         = var.poc
  }
}

data "aws_iam_policy_document" "clair" {
  # Can fetch secrets
  statement {
    actions = ["ssm:GetParameter"]

    resources = [
      aws_ssm_parameter.clair-db-connect-string.arn,
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
      "ecr:BatchGetImage",
    ]
    resources = ["*"]
    effect    = "Allow"
  }

  statement {
    actions = ["sqs:*"]

    resources = [
      aws_sqs_queue.queue.arn,
      "${aws_sqs_queue.queue.arn}/*",
    ]

    effect = "Allow"
  }
}

resource "aws_iam_policy" "clair" {
  name   = "clair"
  policy = data.aws_iam_policy_document.clair.json
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
  role = aws_iam_role.clair.name
  policy_arn = aws_iam_policy.clair.arn
}

data "aws_iam_policy_document" "clair-scanner" {
  # Can fetch secrets
  statement {
    actions = ["s3:*"]

    resources = [
      aws_s3_bucket.bucket.arn,
      "${aws_s3_bucket.bucket.arn}/*",
    ]

    effect = "Allow"
  }
  statement {
    actions = ["sqs:*"]

    resources = [
      aws_sqs_queue.queue.arn,
      "${aws_sqs_queue.queue.arn}/*",
    ]

    effect = "Allow"
  }
  statement {
    actions = ["dynamodb:*"]

    resources = [
      aws_dynamodb_table.indexed-layers.arn,
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
      "ecr:BatchGetImage",
    ]
    resources = ["*"]
    effect = "Allow"
  }
}

resource "aws_iam_policy" "clair-scanner" {
  name = "clair-scanner"
  policy = data.aws_iam_policy_document.clair-scanner.json
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
role       = aws_iam_role.clair-scanner.name
policy_arn = aws_iam_policy.clair-scanner.arn
}

resource "aws_cloudwatch_log_group" "ecs" {
name = "${var.prefix}-clair"

tags = {
Environment = var.environment
Service     = var.service
CostCenter  = var.costcenter
POC         = var.poc
}
}

data "template_file" "clair_task" {
template = file("clair.json")
vars = {
config_parameter_name = "/${var.service}/clair-config.yaml"
log_group             = aws_cloudwatch_log_group.ecs.name
region                = data.aws_region.current.name
sqs_url               = aws_sqs_queue.queue.id
clair_endpoint        = "${aws_lb.clair.dns_name}:6060"
}
}

resource "aws_ecs_task_definition" "clair" {
family                = "${var.prefix}-clair"
container_definitions = data.template_file.clair_task.rendered
task_role_arn         = aws_iam_role.clair.arn
}

resource "aws_lb_target_group" "clair" {
lifecycle {
create_before_destroy = true
}
name_prefix = "clair"
port        = 6060
protocol    = "HTTP"
vpc_id      = module.vpc.vpc_id
target_type = "instance"
health_check {
interval            = 30
path                = "/v1/namespaces"
healthy_threshold   = 2
unhealthy_threshold = 5
}
}

resource "aws_security_group" "clair-private" {
name   = "clair-private"
vpc_id = module.vpc.vpc_id
ingress {
from_port = 6060
to_port   = 6060
protocol  = "tcp"
# TF-UPGRADE-TODO: In Terraform v0.10 and earlier, it was sometimes necessary to
# force an interpolation expression to be interpreted as a list by wrapping it
# in an extra set of list brackets. That form was supported for compatibilty in
# v0.11, but is no longer supported in Terraform v0.12.
#
# If the expression in the following list itself returns a list, remove the
# brackets to avoid interpretation as a list of lists. If the expression
# returns a single list item then leave it as-is and remove this TODO comment.
cidr_blocks = [module.vpc.vpc_cidr_block]
}
egress {
from_port = 32768
to_port   = 60000
protocol  = "tcp"
# TF-UPGRADE-TODO: In Terraform v0.10 and earlier, it was sometimes necessary to
# force an interpolation expression to be interpreted as a list by wrapping it
# in an extra set of list brackets. That form was supported for compatibilty in
# v0.11, but is no longer supported in Terraform v0.12.
#
# If the expression in the following list itself returns a list, remove the
# brackets to avoid interpretation as a list of lists. If the expression
# returns a single list item then leave it as-is and remove this TODO comment.
cidr_blocks = [module.vpc.vpc_cidr_block]
}
tags = {
Environment = var.environment
Service     = var.service
CostCenter  = var.costcenter
POC         = var.poc
}
}

resource "aws_lb" "clair" {
name               = "clair"
internal           = true
load_balancer_type = "application"
security_groups    = [aws_security_group.clair-private.id]
# TF-UPGRADE-TODO: In Terraform v0.10 and earlier, it was sometimes necessary to
# force an interpolation expression to be interpreted as a list by wrapping it
# in an extra set of list brackets. That form was supported for compatibilty in
# v0.11, but is no longer supported in Terraform v0.12.
#
# If the expression in the following list itself returns a list, remove the
# brackets to avoid interpretation as a list of lists. If the expression
# returns a single list item then leave it as-is and remove this TODO comment.
subnets = "${module.vpc.private_subnets}"

tags = {
Name        = "clair-db-subnet"
Environment = var.environment
Service     = var.service
CostCenter  = var.costcenter
POC         = var.poc
}
}

resource "aws_lb_listener" "clair" {
depends_on        = [aws_lb.clair]
load_balancer_arn = aws_lb.clair.arn
port              = "6060"
protocol          = "HTTP"

default_action {
type             = "forward"
target_group_arn = aws_lb_target_group.clair.arn
}
}

resource "aws_ecs_service" "clair" {
depends_on = [
aws_lb_target_group.clair,
aws_lb.clair,
aws_lb_listener.clair,
]
name            = "clair"
cluster         = module.cluster.cluster_id
task_definition = aws_ecs_task_definition.clair.arn
desired_count   = var.number_of_clair_instances

load_balancer {
target_group_arn = aws_lb_target_group.clair.arn
container_name   = "clair"
container_port   = 6060
}
}

data "template_file" "clair-scanner" {
template = file("clair-scanner.json")
vars = {
clair_endpoint = "${aws_lb.clair.dns_name}:6060"
sqs_url        = aws_sqs_queue.queue.id
output_bucket  = aws_s3_bucket.bucket.id
log_group      = aws_cloudwatch_log_group.ecs.name
region         = data.aws_region.current.name
}
}

resource "aws_ecs_task_definition" "clair-scanner" {
family                = "${var.prefix}-clair-scanner"
container_definitions = data.template_file.clair-scanner.rendered
task_role_arn         = aws_iam_role.clair-scanner.arn
}

resource "aws_ecs_service" "clair-scanner" {
name                               = "clair-scanner"
cluster                            = module.cluster.cluster_id
task_definition                    = aws_ecs_task_definition.clair-scanner.arn
desired_count                      = var.number_of_scanners
deployment_minimum_healthy_percent = 0
deployment_maximum_percent         = 100
#   network_configuration {
#     subnets = ["${module.vpc.private_subnets}"]
#     security_groups = ["${aws_security_group.clair-users.id}"]
#   }
}

resource "aws_cloudwatch_event_rule" "putimage" {
name          = "ecr-PutImage"
event_pattern = <<PATTERN
{
  "source": [
    "aws.ecr"
  ],
  "detail": {
    "eventName": [
      "PutImage"
    ]
 }
}
PATTERN

}

resource "aws_cloudwatch_event_target" "lambda" {
rule = aws_cloudwatch_event_rule.putimage.name
arn = aws_lambda_function.putimage.arn
}

resource "aws_iam_role" "iam_for_lambda" {
name_prefix = "lambda-put-image"

assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF

}

resource "aws_iam_policy" "lambda_logging" {
  name        = "lambda_logging"
  path        = "/"
  description = "IAM policy for logging from a lambda"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "arn:aws:logs:*:*:*",
      "Effect": "Allow"
    }
  ]
}
EOF

}

resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role = aws_iam_role.iam_for_lambda.name
  policy_arn = aws_iam_policy.lambda_logging.arn
}

data "aws_iam_policy_document" "lambda_sqs" {
  statement {
    actions = ["sqs:*"]

    resources = [
      aws_sqs_queue.queue.arn,
      "${aws_sqs_queue.queue.arn}/*",
    ]

    effect = "Allow"
  }
}

resource "aws_iam_policy" "lambda_sqs" {
  name = "clair_lambda_sqs"
  policy = data.aws_iam_policy_document.lambda_sqs.json
}

resource "aws_iam_role_policy_attachment" "lambda_sqs" {
  role = aws_iam_role.iam_for_lambda.name
  policy_arn = aws_iam_policy.lambda_sqs.arn
}

resource "aws_lambda_function" "putimage" {
  filename = "putimage.zip"
  function_name = "ecr-cve-monitor-putimage"
  role = aws_iam_role.iam_for_lambda.arn
  handler = "handler.put_image"
  source_code_hash = filebase64sha256("putimage.zip")
  runtime = "python3.6"
  environment {
    variables = {
      SQS_QUEUE_URL = aws_sqs_queue.queue.id
      REGION = data.aws_region.current.name
    }
  }
}

resource "aws_lambda_permission" "allow_cloudwatch" {
  action = "lambda:InvokeFunction"
  function_name = aws_lambda_function.putimage.function_name
  principal = "events.amazonaws.com"
  source_arn = aws_cloudwatch_event_rule.putimage.arn
}

