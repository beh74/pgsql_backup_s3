# pgsql_backup_s3

Backup PostgresSQL database using pg_dumpall and upload sql backup file to S3 (with periodic backups by using restart_policy) in a **docker swarm environment** with a tiny alpine image (150 MB).
S3 bucket destinations must be versionned : we will use S3 versioning to restore a specific version

By convention, the postgresql dbname will be the UNIQUE ID of the file uploaded to S3.

We will tag the S3 object with :
- dump-type : postgresql  (because i need to know the backup kind)
- dump-time : database pg_dumpall time in seconds (because i need to estimate the db restauration time)
- database-version : the postgresql server version discovered during backup

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
      - postgres
    links:
      - postgres
    environment:
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
    deploy:
      restart_policy:
        condition: any
        # Backup every hour
        delay: 1h
```

### Automatic Periodic Backups

The container will stop after each backup. To schedule backup, use restart_policy to define periodicity of backups 

### Endpoints for S3

An Endpoint is the URL of the entry point for an AWS web service or S3 Compatible Storage Provider.

You can specify an alternate endpoint by setting `S3_ENDPOINT` environment variable like `protocol://endpoint`

**Note:** S3 Compatible Storage Provider like minio or scality requires `S3_ENDPOINT` environment variable
