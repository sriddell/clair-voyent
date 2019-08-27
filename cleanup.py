import boto3
import json
import sys

# Prototype to remove s3 records and dynamodb records for images that have been removed from ECR.
# Right now, the list_repos.py has to be run under 10011 credentials to build the list of all repos,
# then this script runs under 10021 credentials to remove s3 reports and dynamodb entries for any repos that
# no longer exist, so we don't report on them, or trigger clair layer notifications for them.
# This should be wrapped into lambda functions to run periodically, or on notification of a delete
# from ECR
BUCKET = 'ecrscan-clair-scan-results'
raw = None
with open(sys.argv[1]) as f:
    raw = json.load(f)

images = {}
for image in raw:
    registryId = image['registryId']
    repository = image['repository']
    imageDigest = image['imageDigest'].split('sha256:')[1]
    if registryId not in images.keys():
        images[registryId] = {}
    if repository not in images[registryId].keys():
        images[registryId][repository] = set()
    if imageDigest not in images[registryId][repository]:
        images[registryId][repository].add(imageDigest)

s3 = boto3.client('s3')
reports = []
response = s3.list_objects_v2(
    Bucket=BUCKET
)
for k in response['Contents']:
    reports.append(k['Key'])
continuationToken = None
if response['IsTruncated']:
    continuationToken = response['NextContinuationToken']
while continuationToken is not None:
    response = s3.list_objects_v2(
        Bucket=BUCKET,
        ContinuationToken=continuationToken
    )
    for k in response['Contents']:
        reports.append(k['Key'])
    continuationToken = None
    if response['IsTruncated']:
        continuationToken = response['NextContinuationToken']

to_delete = []
for key in reports:
    # value='year=2019/month=08/day=09/registry_id=434313288222/prod/workflow-api/457531f2efe6475baef56af1248930f46bc8b7992bedfb072248fc8ec38250b6.json.gz'
    value = key
    value = value.split('/', 1)[1]
    value = value.split('/', 1)[1]
    value = value.split('/', 1)[1]
    values = value.split('/', 1)
    registry_id = values[0].split('registry_id=')[1]
    value = values[1]
    values = value.split('/')
    repository = '/'.join(values[:-1])
    image_digest = values[-1].split('.json.gz')[0]
    # print(registry_id)
    # print(repo_name)
    # print(image_digest)
    delete = True
    if not (registry_id in images and repository in images[registry_id] and image_digest in images[registry_id][repository]):
        to_delete.append(key)

print("Deleting s3 reports:")
for k in to_delete:
    print(k)
    s3.delete_object(
        Bucket=BUCKET,
        Key=k
    )


def should_delete_from_db(item, images):
    registryId = item['image_data']['M']['registryId']['S']
    repository = item['image_data']['M']['repositoryName']['S']
    imageDigest = item['image_data']['M']['imageId']['M']['imageDigest']['S']
    imageDigest = imageDigest.split('sha256:')[1]
    exists = registryId in images and repository in images[registryId] and imageDigest in images[registryId][repository]
    return not exists


to_delete = []
db = boto3.client('dynamodb')
response = db.scan(
    TableName='clair-indexed-layers',
    ConsistentRead=True
)
for item in response['Items']:
    if should_delete_from_db(item, images):
        to_delete.append({
            'layer_name': item['layer_name']['S'],
            'image_name': item['image_name']['S']
        })
last_evaluated_key = None
if 'LastEvaluatedKey' in response:
    last_evaluated_key = response['LastEvaluatedKey']
while last_evaluated_key is not None:
    response = db.scan(
        TableName='clair-indexed-layers',
        ConsistentRead=True,
        ExclusiveStartKey=last_evaluated_key
    )
    if should_delete_from_db(item, images):
        to_delete.append({
            'layer_name': item['layer_name']['S'],
            'image_name': item['image_name']['S']
        })
    last_evaluated_key = None
    if 'LastEvaluatedKey' in response:
        last_evaluated_key = response['LastEvaluatedKey']

print("delete dynamodb records:")
for item in to_delete:
    print(item)
    db.delete_item(
        TableName='clair-indexed-layers',
        Key={
            'layer_name': {
                'S': item['layer_name']
            },
            'image_name': {
                'S': item['image_name']
            }
        }
    )
