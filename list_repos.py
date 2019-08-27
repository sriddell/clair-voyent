import boto3
import json

registries = ['434313288222']
existing_repos = []
ecr = boto3.client('ecr')
for r in registries:
    response = ecr.describe_repositories(
        registryId=str(r)
    )
    for repo in response['repositories']:
        t = (r, repo['repositoryName'])
        if t not in existing_repos:
            existing_repos.append(t)
    nextToken = None
    if 'nextToken' in response.keys():
        nextToken = response['nextToken']
    while nextToken is not None:
        response = ecr.describe_repositories(
            registryId=r,
            nextToken=nextToken
        )
        for repo in response['repositories']:
            t = (r, repo['repositoryName'])
            if t not in existing_repos:
                existing_repos.append(t)
            nextToken = None
        if 'nextToken' in response.keys():
            nextToken = response['nextToken']

existing_images = []
for repo in existing_repos:
    response = ecr.describe_images(
        registryId=str(repo[0]),
        repositoryName=str(repo[1])
    )
    for image in response['imageDetails']:
        t = (r, repo[1], image['imageDigest'])
        if t not in existing_images:
            existing_images.append(t)
    nextToken = None
    if 'nextToken' in response.keys():
        nextToken = response['nextToken']
    while nextToken is not None:
        response = ecr.describe_images(
            registryId=repo[0],
            repositoryName=repo[1],
            nextToken=nextToken
        )
        for image in response['imageDetails']:
            t = (r, repo[1], image['imageDigest'])
            if t not in existing_images:
                existing_images.append(t)
        nextToken = None
        if 'nextToken' in response.keys():
            nextToken = response['nextToken']

images = []
for t in existing_images:
    images.append({
        'registryId': t[0],
        'repository': t[1],
        'imageDigest': t[2]
    })

print(json.dumps(images))
