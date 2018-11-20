import json
import os
import boto3


def put_image(event, context):
    endpoint = None
    if 'SQS_ENDPOINT' in os.environ:
        endpoint = os.environ['SQS_ENDPOINT']
    print('using endpoint ' + endpoint)
    sqs = boto3.resource('sqs', region_name=os.environ['REGION'], endpoint_url=endpoint)
    queue = sqs.Queue(os.environ['SQS_QUEUE_URL'])
    j = json.loads(event)
    msg = {'CloudWatchEvent': j}
    queue.sendMessage(MessageBody=json.dumps(msg))

    return {
        'statusCode': 200,
        'body': 'Queued message'
    }
