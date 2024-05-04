# pgsql_backup_s3

Backup PostgresSQL database using pg_dumpall and upload sql backup file to S3 (with periodic backups by using restart_policy) in a **docker swarm environment** with a tiny alpine image (150 MB).
S3 bucket destinations must be versionned : we will use S3 versioning to restore a specific version

Supported PostgresSQL versions : from 9.6 to 16.2

![Alt text](images/design.jpg?raw=true "Big picture")

## Usage

Docker Compose:
```yaml
version: '3.7'

services:
  mypostgres:
    image: postgres
    environment:
      POSTGRES_USER: myuser
      POSTGRES_PASSWORD: mypassword
      POSTGRES_DATABASE: mydb

  pgbackups3:
    image: pqsql-backup-s3:1.0
    depends_on:
      - mypostgres
    links:
      - mypostgres
    environment:
      S3_ENDPOINT: https://mys3.local
      S3_REGION: region
      S3_ACCESS_KEY_ID: key
      S3_SECRET_ACCESS_KEY: secret
      S3_BUCKET: my-bucket
      S3_PREFIX: backup
      POSTGRES_HOST: mypostgres
      POSTGRES_DATABASE: mydb
      POSTGRES_USER: myuser
      POSTGRES_PASSWORD: mypassword
      POSTGRES_EXTRA_OPTS: '--schema=public --blobs'
      SLACK_URL: https://hooks.slack.com/services/xxxx
      ELASTIC_URL: https://user:password@myelastic.local/indexname/_doc
    deploy:
      restart_policy:
        condition: any
        # Backup every hour
        delay: 1h
```
### Backup file

If BACKUP_FILENAME env var is not provided, then the backup file name is set to POSTGRES_DATABASE env var

The filename will be tagged in S3 object :
- dump-type : postgresql 
- dump-time : database pg_dumpall time in seconds (to estimate the db restauration time)
- database-version : the postgresql server version discovered during backup

You may have to define a S3 life cycle managment rule to delete old backups in the destination bucket.


### Automatic Periodic Backups

The container will stop after each backup. To schedule backup, use restart_policy to define periodicity of backups 

### Slack notification when backup fails

If the SLACK_URL environment variable is set, a notification will be sent to Slack on any backup error

### Elasticsearch

If the ELASTIC_URL environment variable is set, all informations relative to backup will be stored in an index even in case of a backup failure.
The ELASTIC_URL should be : https://user:password@myelastic.local/indexname/_doc

### Endpoints for S3

An Endpoint is the URL of the entry point for an AWS web service or S3 Compatible Storage Provider.

You can specify an alternate endpoint by setting `S3_ENDPOINT` environment variable like `protocol://endpoint`

**Note:** S3 Compatible Storage Provider like minio or scality requires `S3_ENDPOINT` environment variable

### Database restore

Check the restore folder in this repository that contains all the code needed to restore a database from a s3 object
