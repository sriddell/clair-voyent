import boto3
import time
import json
import csv
import botocore
import os
import uuid
import re
import sys
from datetime import datetime, timedelta, timezone, date


partitions = None
start = datetime(int(sys.argv[3]), int(sys.argv[1]), int(sys.argv[2]))
stop = datetime(int(sys.argv[6]), int(sys.argv[4]), int(sys.argv[5]))
cutoff = datetime(year=int(sys.argv[9]), month=int(sys.argv[7]), day=int(sys.argv[8]), hour=0, minute=0, second=0, tzinfo=timezone.utc)

day = start
partitions = []
while day <= stop:
    partitions.append({
        'year': str(day.year),
        'month': str(day.month).zfill(2),
        'day': str(day.day).zfill(2)
    })
    day = day + timedelta(days=1)

date_handler = lambda obj: (
    obj.isoformat()
    if isinstance(obj, (datetime, date))
    else None
)

athena = boto3.client('athena')
ecr = boto3.client('ecr')


def execute_query(query_string):
    result = athena.start_query_execution(
        QueryString=query_string,
        QueryExecutionContext={
            'Database': 'ecrreports'
        },
        ResultConfiguration={
            'OutputLocation': 's3://ecr-clair-scan-results'
        }
    )

    q_execution_id = result['QueryExecutionId']

    status = 'RUNNING'
    response = None
    while status == 'RUNNING':
        time.sleep(3)
        response = athena.batch_get_query_execution(
            QueryExecutionIds=[q_execution_id]
        )
        status = response['QueryExecutions'][0]['Status']['State']
    if status != "SUCCEEDED":
        print(response)
        raise Exception("Failed, status is " + status)
    return q_execution_id


def update_details(vulnerable_images, repo, details, imageDetails):
    for image in imageDetails:
        t = (repo[0], repo[1], image['imageDigest'])
        if t in vulnerable_images:
            if t not in details:
                details[t] = {'tags': [], 'imagePushedAt': None}
                details[t]['imagePushedAt'] = image['imagePushedAt']
            if 'imageTags' in image.keys():
                details[t]['tags'] = image['imageTags']


table_name = 'reports_' + re.sub('[-]', '', str(uuid.uuid4()))
table_def = 'CREATE external TABLE ' + table_name + ' ('
table_def = table_def + '''
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
ROW FORMAT SERDE 'org.openx.data.jsonserde.JsonSerDe' LOCATION 's3://ecrscan-clair-scan-results/'
'''
drop_table = 'DROP TABLE `' + table_name + '`;'


execute_query(table_def)

if partitions is None:
    execute_query("MSCK REPAIR TABLE " + table_name)  # load all data
else:
    for partition in partitions:
        add_partition = "ALTER TABLE " + table_name + " ADD PARTITION (year='" + partition['year'] + "',month='" + partition['month'] + "',day='" + partition['day'] + "') location 's3://ecrscan-clair-scan-results/year=" + partition['year'] + "/month=" + partition['month'] + "/day=" + partition['day'] + "/'"
        execute_query(add_partition)


query_string = "select distinct ECRMetadata.registryId, ECRMetadata.repositoryName, ECRMetadata.imageId.imageDigest from " + table_name + " where cardinality(vulnerabilities.High) > 0 order by ECRMetadata.registryId, ECRMetadata.repositoryName, ECRMetadata.imageId.imageDigest;"
q_execution_id = execute_query(query_string)
execute_query(drop_table)

s3_key = q_execution_id + '.csv'
local_filename = q_execution_id + '.csv'
s3 = boto3.resource('s3')
try:
    s3.Bucket('ecr-clair-scan-results').download_file(s3_key, local_filename)
except botocore.exceptions.ClientError as e:
    if e.response['Error']['Code'] == "404":
        print("The object does not exist.")
    else:
        raise

# read file to array
vulnerable_images = []
with open(local_filename) as csvfile:
    reader = csv.DictReader(csvfile)
    for row in reader:
        vulnerable_images.append((row['registryid'], row['repositoryname'], row['imagedigest']))
# delete result file
if os.path.isfile(local_filename):
    os.remove(local_filename)
repos = set()
registries = set()
for row in vulnerable_images:
    t = (row[0], row[1])
    if t not in repos:
        repos.add(t)
    if row[0] not in registries:
        registries.add(row[0])

details = {}
for k in repos:
    try:
        response = ecr.describe_images(
            registryId=k[0],
            repositoryName=k[1]
        )

        update_details(vulnerable_images, k, details, response['imageDetails'])
        nextToken = None
        if 'nextToken' in response.keys():
            nextToken = response['nextToken']
        while nextToken is not None:
            response = ecr.describe_images(
                registryId=k[0],
                repositoryName=k[1],
                nextToken=nextToken
            )
            update_details(vulnerable_images, k, details, response['imageDetails'])
            nextToken = None
            if 'nextToken' in response.keys():
                nextToken = response['nextToken']
    except botocore.exceptions.ClientError:
        # ideally, we would list all repos, then filter out reports for repos which have been deleted
        # unfortunately, listing all repos cross account doesn't seem to be working; have reached out to
        # aws on this
        continue

# Note that the tags map may contain fewer images than generated in the report, this is because
# an ecr image may have been deleted after it was scanned.
report = {
    'partitions': partitions,
    'high_vulnerabilities': []
}
report['high_vulnerabilities'] = []
for k in details.keys():
    out = {
        'registryId': k[0],
        'repositoryName': k[1],
        'imageId': k[2],
        'tags': details[k]['tags'],
        'imagePushedAt': details[k]['imagePushedAt']
    }
    report['high_vulnerabilities'].append(out)

report['high_vulnerabilities'] = list(filter(lambda x: (x['imagePushedAt'] >= cutoff), report['high_vulnerabilities']))
report['high_vulnerabilities'].sort(key=lambda x: x['imagePushedAt'], reverse=True)
print(json.dumps(report, default=date_handler))
