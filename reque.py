import boto3

sqs = boto3.resource('sqs')
queue = sqs.Queue('https://sqs.us-east-1.amazonaws.com/234324814398/ecrscan-clair-dead-letter')
to_queue = sqs.Queue('https://sqs.us-east-1.amazonaws.com/234324814398/ecrscan-clair-index-requests')
while True:
    msgs = queue.receive_messages(
        VisibilityTimeout=20 * 60,
        WaitTimeSeconds=20
    )
    if len(msgs) > 0:
        for msg in msgs:
            to_queue.send_message(MessageBody=msg.body)
            msg.delete()
