from psycopg2 import connect, IntegrityError
from psycopg2.extensions import ISOLATION_LEVEL_AUTOCOMMIT, ISOLATION_LEVEL_READ_COMMITTED
import boto3
import os
import subprocess
import json

DB_NAME = 'vulnscanning'


def create_database(event, context):
    con = _new_connection()

    con.set_isolation_level(ISOLATION_LEVEL_AUTOCOMMIT)
    cur = con.cursor()
    cur.execute('CREATE DATABASE ' + DB_NAME)
    cur.close()
    con.close()
    body = {
        "message": "DB created",
    }

    response = {
        "statusCode": 200,
        "body": json.dumps(body)
    }

    return response

    # Use this code if you don't use the http event with the LAMBDA-PROXY
    # integration
    """
    return {
        "message": "Go Serverless v1.0! Your function executed successfully!",
        "event": event
    }
    """


def create_table(event, context):
    con = _new_connection()

    con.set_isolation_level(ISOLATION_LEVEL_AUTOCOMMIT)
    cur = con.cursor()
    st = ['DROP TABLE if exists layers cascade;']
    st.append('''CREATE TABLE IF NOT EXISTS layers (
        layer_digest varchar(512) not null,
        registry_id varchar(512) not null,
        repo_name varchar(512) not null,
        image_tag varchar(512) not null
    )
    ''')
    st.append('create index layer on layers (layer_digest)')
    st.append('create index registry on layers (registry_id)')
    st.append('create index repo on layers (repo_name)')
    st.append('create index tag on layers (image_tag)')
    st.append('alter table layers add constraint no_dupes unique (layer_digest, registry_id, repo_name, image_tag)')
    for s in st:
        cur.execute(s)
    cur.close()
    con.close()
    body = {
        "message": "table created",
    }

    response = {
        "statusCode": 200,
        "body": json.dumps(body)
    }

    return response


def shane(event, context):
    con = _new_connection()
    cur = con.cursor()
    cur.execute('select layer_digest, count(layer_digest) from layers group by layer_digest having count(layer_digest) > 1')
    for record in cur:
        print(record)


def index_image(event, context):
    ecr = boto3.client('ecr')
    token = ecr.get_authorization_token(registryIds=['434313288222'])['authorizationData'][0]['authorizationToken']
    clair_addr = os.environ['CLAIR_ADDR']
    result = subprocess.run(["./klar", event['image']], check=True, env={"DOCKER_USER": "AWS", "DOCKER_PASSWORD": token, "CLAIR_ADDR": clair_addr})
    print(result)
    return {
        "statuCode": 200,
        "body": result
    }


def record_layers(event, context):
    ecr = boto3.client('ecr')
    registry_id = event['registry_id']
    repo_name = event['repo_name']
    image_tag = event['image_tag']
    resp = ecr.batch_get_image(
        registryId=registry_id, repositoryName=repo_name,
        imageIds=[{'imageTag': image_tag}]
    )

    manifest = json.loads(resp['images'][0]['imageManifest'])
    print(manifest)
    layers = []
    if manifest['schemaVersion'] == 2:
        for layer in manifest['layers']:
            layers.append(layer['digest'])
    elif manifest['schemaVersion'] == 1:
        for layer in manifest['fsLayers']:
            layers.append(layer['blobSum'])
    print('layers:')
    print(layers)

    con = _new_connection()
    con.set_isolation_level(ISOLATION_LEVEL_READ_COMMITTED)

    for layer_digest in layers:
        cur = con.cursor()
        st = "insert into layers (layer_digest, registry_id, repo_name, image_tag) values (%s,%s,%s,%s)"
        data = (layer_digest, registry_id, repo_name, image_tag)
        try:
            cur.execute(st, data)
        except IntegrityError:
            print('Already have layer record, ignoring ' + str(data))
            con.rollback()
        else:
            con.commit()
        con.commit()
        cur.close()
    con.close()
    response = {
        "statusCode": 200,
        "body": 'success'
    }
    return response


def read_layers(event, context):
    con = _new_connection()
    cur = con.cursor()
    cur.execute('select * from layers;')
    result = {'records': []}
    for record in cur:
        result['records'].append(record)
    cur.close()
    con.close()
    response = {
        "statusCode": 200,
        "body": json.dumps(result)
    }
    return response


def get_images_for_layer(event, context):
    con = _new_connection()
    cur = con.cursor()
    cur.execute('select * from layers where layer_digest=%s', (event['layer_digest'],))
    result = {'records': []}
    for record in cur:
        result['records'].append(record)
    cur.close()
    con.close()
    return {
        "statusCode": 200,
        "body": json.dumps(result)
    }


def _new_connection():
    stage = os.environ['STAGE']
    ssm = boto3.client('ssm')
    host = ssm.get_parameter(Name='clair-' + stage + '-db-host')['Parameter']['Value']
    password = ssm.get_parameter(Name='clair-' + stage + '-db-password')['Parameter']['Value']

    return connect(dbname=DB_NAME, host=host, user='postgres', password=password)
