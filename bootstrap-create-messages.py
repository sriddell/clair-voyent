import boto3
import json

# Should work iwth any version of python 3 with boto3 available.
# Make sure you have exported AWS credentials for the account that contains the ECR registry
# into your shell before running this script.
# Scans an ECR registry, outputting scan request messages for all images found in all repositories.
# To use, set REGISTRY_ID to the registry ID you wish to bootstrap.
# Redirect the output to output.json
# python bootstrap-create-messages > output.json.

# Note that this currently assumes the registry is in us-east-1

client = boto3.client('ecr')

REGISTRY_ID = ''
resp = client.describe_repositories(
    registryId=REGISTRY_ID,
    maxResults=100
)
repos = []
for r in resp['repositories']:
    repos.append(r)
next_token = None
if 'nextToken' in resp:
    next_token = resp['nextToken']
while next_token is not None:
    resp = client.describe_repositories(
        registryId='434313288222',
        maxResults=100,
        nextToken=next_token
    )
    for r in resp['repositories']:
        repos.append(r)
    next_token = None
    if 'nextToken' in resp:
        next_token = resp['nextToken']

messages = []
base = 'aws sqs send-message --queue-url %s --message-body \'{"ScanImage":{"awsRegion": "us-east-1", "repositoryName": "%s", "registryId": "%s", "imageId": {"imageDigest": "%s"}}}\''
for r in repos:
    resp = client.list_images(
        registryId=REGISTRY_ID,
        repositoryName=r['repositoryName'],
        maxResults=100
    )
    for i in resp['imageIds']:
        msg = {
            'ScanImage': {
                'awsRegion': 'us-east-1',
                'repositoryName': r['repositoryName'],
                'registryId': REGISTRY_ID,
                'imageId': {'imageDigest': i['imageDigest']}
            }
        }
        messages.append(msg)
    next_token = None
    if 'nextToken' in resp:
        next_token = resp['nextToken']
    while next_token is not None:
        resp = client.list_images(
            registryId=REGISTRY_ID,
            repositoryName=r['repositoryName'],
            maxResults=100,
            nextToken=next_token
        )
        for i in resp['imageIds']:
            msg = {
                'ScanImage': {
                    'awsRegion': 'us-east-1',
                    'repositoryName': r['repositoryName'],
                    'registryId': REGISTRY_ID,
                    'imageId': {'imageDigest': i['imageDigest']}
                }
            }
            messages.append(msg)
        next_token = None
        if 'nextToken' in resp:
            next_token = resp['nextToken']

print(json.dumps(messages))
