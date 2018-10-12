import boto3
import yaml
import os

stage = os.environ['STAGE']
ssm = boto3.client('ssm')
host = ssm.get_parameter(Name='clair-' + stage + '-db-host')['Parameter']['Value']
password = ssm.get_parameter(Name='clair-' + stage + '-db-password')['Parameter']['Value']
config = None
with open('/clair/clair-config.yaml', 'r') as stream:
    config = yaml.load(stream)
config['clair']['database']['options']['source'] = 'host=' + host + ' dbname=ClairDb user=postgres password=' + password
print(config)
with open('/clair/clair-config.yaml', 'w') as outfile:
    yaml.dump(config, outfile, width=float("inf"), default_flow_style=False)