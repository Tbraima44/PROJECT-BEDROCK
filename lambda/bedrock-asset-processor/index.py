# Lambda function handler for S3 asset processing
import json
import boto3
import os

def handler(event, context):
    """
    Lambda function triggered by S3 upload events.
    Logs the uploaded file name to CloudWatch.
    """
    print("Received event: " + json.dumps(event, indent=2))
    
    # Get the object from the event
    bucket = event['Records'][0]['s3']['bucket']['name']
    key = event['Records'][0]['s3']['object']['key']
    
    print(f"Image received: {key}")
    
    return {
        'statusCode': 200,
        'body': json.dumps(f'Successfully processed {key}')
    }