import boto3
import json
import sys
import subprocess

# date_handler = lambda obj: (
#     obj.isoformat()
#     if isinstance(obj, (datetime.datetime, datetime.date))
#     else None
# )
ecr = boto3.client('ecr')
s3 = boto3.resource('s3')
to_quarantine = []
with open(sys.argv[1]) as json_file:
    to_quarantine = json.load(json_file)
for q in to_quarantine:
    image_name = q['registryId'] + '.dkr.ecr.us-east-1.amazonaws.com/' + q['repositoryName'] + '@' + q['imageId']
    subprocess.run(['docker', 'pull', image_name])
    imageId = q['imageId'].split('sha256:')[1]
    archive_name = imageId + '.tar'
    with open(imageId + '.json', 'w') as outfile:
        json.dump(q, outfile)
    subprocess.run(['docker', 'save', image_name, '-o', archive_name])
    s3.Bucket('10011-ecr-quarantine').upload_file(
        Filename=imageId + '.json',
        Key=q['registryId'] + '/' + q['repositoryName'] + '/' + imageId + '/' + imageId + '.json'
    )
    s3.Bucket('10011-ecr-quarantine').upload_file(
        Filename=archive_name,
        Key=q['registryId'] + '/' + q['repositoryName'] + '/' + imageId + '/' + archive_name
    )
    ecr.batch_delete_image(
        registryId=q['registryId'],
        repositoryName=q['repositoryName'],
        imageIds=[
            {
                'imageDigest': q['imageId']
            }
        ]
    )

