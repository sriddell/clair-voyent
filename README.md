# ecr-cve-monitor

This project is a working Proof-of-Concept of using the [coreos/Clair project](https://github.com/coreos/clair) to scan all images pushed to an AWS ECR registry, and to automatically rescan them if Clair detects a new CVE that affects a known image.

See ecr-cve-monitor.md for more details on the purpose and architecture of the project.

## Installation

Make sure you have terraform 0.11.13 or greater in the 0.11.x release series available.

Create a terraform.tfvars file and define the following values:

```
environment="environment name, like cicd or dev"
costcenter="costcenter identifier"
poc="point of contact email"
service="ecr-cve-monitor"

ecs_ami_id="latest ECS cluster AMI id for your deployment region"
key_name="ssh key for ec2 instances"
instance_type="instance type for the ecs cluster, I use m5.xlarge for the default installation settings for memory and cpu usage"

number_of_clair_instances=1
number_of_scanners=1
number_of_ecs_instances=2

prefix="a prefix to use for all resources created"
```

Run terraform init, then terraform plan to look at the plan that will be generated, then apply the changes.
A new VPC with an ECS cluster running the ecr-cve-monitor software, along with the message queue, dead-letter queue, dynamodb tables, and a CloudWatch event to trigger a lambda to queue up an image scan anytime a new image is pushed to the ecr registry in this account will be created.

Note that if you want to install to an existing VPC and/or an existing ECS cluster, you can modify the main.tf file to do so.

Also, while the underlying image layer tracking is capable of supporting multiple registries (in different regions/accounts), it has not yet been tested, and you would need to modify the terraform to allow CloudWatch events from the other registry to be pushed onto the ecr-cve-monitor input queue.

### Bootstrapping

Note that you should let the clair service deployed by terraform run for at least 60 minutes so that it can do the initial CVE database load.  While Clair is loading the initial CVEs, it will generate empty reports, but disables generating notifications for CVEs as they come in - so basically, if you bootstrap too soon, you will have to repeat it to get accurate first-time reports.

Run the bootstrap-create-messages.py and bootstrap-load-message.py (comments in the files contain instructions on how to run them.)  Basically, these scan a registry for all existing images, and queue a scan request for each image so that they become known to and monitored by clair, and generate an initial report to s3.

Note that if you have a lot of images to go through initially, you may want to temporarily adjust the terraform.tfvars for number_of_clair_instances, number_of_scanners, and number_of_ecs_instances to get through the backlog more quickly.  During testing, we found that a clair_instance could typically handle about 8 clair scanners at once.

## Reporting

### Setting up reporting

In AWS Glue, create a database for reporting on the scan results.  Then in AWS Athena, create an external table like so:

```
CREATE external TABLE reports (
         LayerCount int,
AnalyzedImageName string,
  ImageDigest string,
  ECRMetadata struct<
  imageId:struct<imageDigest:string>,
  manifest:struct<config:struct<digest:string>>,
  repositoryName:string,
  registryId:string
>,

         Vulnerabilities struct< High:array<struct<Name:string,
         NamespaceName:string,
         Description:string,
         Link:string,
         Severity:string>>,
         Medium:array<struct<Name:string,
         NamespaceName:string,
         Description:string,
         Link:string,
         Severity:string>>,
         Medium:array<struct<Name:string,
         NamespaceName:string,
         Description:string,
         Link:string,
         Severity:string>>,
         Medium:array<struct<Name:string,
         NamespaceName:string,
         Description:string,
         Link:string,
         Severity:string>>,
         Low:array<struct<Name:string,
         NamespaceName:string,
         Description:string,
         Link:string,
         Severity:string>>,
         Medium:array<struct<Name:string,
         NamespaceName:string,
         Description:string,
         Link:string,
         Severity:string>>,
         Negligible:array<struct<Name:string,
         NamespaceName:string,
         Description:string,
         Link:string,
         Severity:string>>,
         Medium:array<struct<Name:string,
         NamespaceName:string,
         Description:string,
         Link:string,
         Severity:string>>
          >
)
PARTITIONED BY(year string, month string, day string)
ROW FORMAT SERDE 'org.openx.data.jsonserde.JsonSerDe' LOCATION 's3://my-report-bucket/'
```

Be sure to replace the LOCATION s3://my-report-bucket with the terraform output 'report_bucket' that specifies your own report bucket name

### Reporting with Athena

To report with athena, you can load all partions with

```
MSCK REPAIR TABLE reports
```

However, typically, you do not need to creates reports across the entire time series, and will only be interested in seeing new reports (either new CVEs that affected existing image, or that exist in newly pushed images) for a given time range.  To do that more cheaply and efficiently, load just the partitions that correspond to the time range you want to query.

For example, to load and report on January 15 of 2019:

```
ALTER TABLE reports ADD PARTITION (year='2019',month='01',day='15') location 's3://ellucian-clair-scan-results/year=2019/month=01/day=15/'
```

You can then query for any images that were detected to have at least 1 High CVE on the 15th.

```
select distinct ECRMetadata.registryId, ECRMetadata.repositoryName, ECRMetadata.imageId.imageDigest from reports where cardinality(vulnerabilities.High) > 0 and year='2019' and month='01' and day='15' order by ECRMetadata.registryId, ECRMetadata.repositoryName, ECRMetadata.imageId.imageDigest;
```

Note that this will give you back results in terms of the internal registry ID of the image.  You can use the AWS SDKs to convert this to a (current) list of human friendly tags.  The Athena reporting itself, and the internal report structures cannot use human-friendly image tags because they are not immutable.

## High level diagram

![Architecture](ecr-cve-monitor.png)

## Disaster recovery

Any loss of information can be recovered by repopulating the reports from scratch (except historical time-series data).

## Why Clair

* From CoreOS team
* Opensource
* Used to power vulnerability scanning in Quay.io
* Can generate reports without re-consuming layers
* Can raise new vulnerabilities against existing layers without actually rescanning the image
