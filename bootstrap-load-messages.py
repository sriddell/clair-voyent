import boto3
import json

# Should work iwth any version of python 3 with boto3 available.
# Make sure you have exported AWS credentials for the account that message queue output from
# the terraform variable output variable
# input_queue.  set QUEUE_URL to the URL of the
# SQS queue created for scan requests by the terraform script, which will be the output variable
# input_queue.


QUEUE_URL = ''
client = boto3.client('sqs')

messages = []
with open('output.json') as f:
    messages = json.load(f)

print('loaded messages')
count = 0
for msg in messages:
    client.send_message(
        QueueUrl=QUEUE_URL,
        MessageBody=json.dumps(msg)
    )
    count = count + 1
    if (count % 100) == 0:
        print(count)
