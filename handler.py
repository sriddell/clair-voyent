import json
import os
import boto3


def put_image(event, context):
    endpoint = None
    if 'SQS_ENDPOINT' in os.environ:
        endpoint = os.environ['SQS_ENDPOINT']
    sqs = boto3.resource('sqs', region_name=os.environ['REGION'], endpoint_url=endpoint)
    queue = sqs.Queue(os.environ['SQS_QUEUE_URL'])
    msg = {'CloudWatchEvent': event}
    queue.send_message(MessageBody=json.dumps(msg))

    return {
        'statusCode': 200,
        'body': 'Queued message'
    }
