#! /bin/sh

set -e
#trap 'catch $? $LINENO' EXIT

function notify {
  echo "Backup failed for :"
  echo "db host : ${POSTGRES_HOST}"
  echo "db name : ${POSTGRES_DATABASE}"
  echo "db port : ${POSTGRES_PORT}"
  echo "db user : ${POSTGRES_USER}"
  echo "s3 bucket : ${S3_BUCKET}"
  echo "s3 prefix : ${S3_PREFIX}"
  echo "backup container hostname : $HOSTNAME"

  if [ "${SLACK_URL}" = "**None**" ]; then
    echo "SLACK_URL is undefined. Skipping Slack notification"
  else
    echo "Sending a notification to Slack"
    payload='
    {
    "title": "Backup failed !",
    "attachments": [
    {
    "author_name": "From container '"$HOSTNAME"'",
    "text": "PostgreSql backup failed",
    "color": "#00a3e0"
    },
    {
     "text": "Database : '"${POSTGRES_USER}"'@'"${POSTGRES_HOST}"':'"${POSTGRES_PORT}"'/'"${POSTGRES_DATABASE}"'"
    },
    {
     "text": "S3 : '"${S3_BUCKET}"'/'"${S3_PREFIX}"'"
    }
    ]
    }'
    curl -s -X POST -H "Content-type: application/json" -d "$payload" $SLACK_URL

  fi
}
trap notify EXIT

if [ "${S3_ACCESS_KEY_ID}" = "**None**" ]; then
  echo "You need to set the S3_ACCESS_KEY_ID environment variable."
  exit 1
fi

if [ "${S3_SECRET_ACCESS_KEY}" = "**None**" ]; then
  echo "You need to set the S3_SECRET_ACCESS_KEY environment variable."
  exit 1
fi

if [ "${S3_BUCKET}" = "**None**" ]; then
  echo "You need to set the S3_BUCKET environment variable."
  exit 1
fi

if [ "${POSTGRES_DATABASE}" = "**None**" -a "${POSTGRES_BACKUP_ALL}" != "true" ]; then
  echo "You need to set the POSTGRES_DATABASE environment variable."
  exit 1
fi

if [ "${POSTGRES_HOST}" = "**None**" ]; then
  if [ -n "${POSTGRES_PORT_5432_TCP_ADDR}" ]; then
    POSTGRES_HOST=$POSTGRES_PORT_5432_TCP_ADDR
    POSTGRES_PORT=$POSTGRES_PORT_5432_TCP_PORT
  else
    echo "You need to set the POSTGRES_HOST environment variable."
    exit 1
  fi
fi

if [ "${POSTGRES_USER}" = "**None**" ]; then
  echo "You need to set the POSTGRES_USER environment variable."
  exit 1
fi

if [ "${POSTGRES_PASSWORD}" = "**None**" ]; then
  echo "You need to set the POSTGRES_PASSWORD environment variable or link to a container named POSTGRES."
  exit 1
fi

if [ "${S3_ENDPOINT}" == "**None**" ]; then
  AWS_ARGS=""
else
  AWS_ARGS="--endpoint-url ${S3_ENDPOINT}"
fi

# env vars needed for aws tools
export AWS_ACCESS_KEY_ID=$S3_ACCESS_KEY_ID
export AWS_SECRET_ACCESS_KEY=$S3_SECRET_ACCESS_KEY
export AWS_DEFAULT_REGION=$S3_REGION

export PGPASSWORD=$POSTGRES_PASSWORD
POSTGRES_HOST_OPTS="-h $POSTGRES_HOST -p $POSTGRES_PORT -U $POSTGRES_USER $POSTGRES_EXTRA_OPTS"

if [ -z ${S3_PREFIX+x} ]; then
  S3_PREFIX="/"
else
  S3_PREFIX="/${S3_PREFIX}/"  
fi

echo "Connecting PostgreSql server to get the server version"
sqlver=`psql -t -h $POSTGRES_HOST -p $POSTGRES_PORT -U $POSTGRES_USER -d $POSTGRES_DATABASE -c "SHOW server_version;"`

echo "Creating dump of all databases from ${POSTGRES_HOST} version ${sqlver}..."
start=`date +%s`
pg_dumpall -h $POSTGRES_HOST -p $POSTGRES_PORT -U $POSTGRES_USER | gzip > /home/bckuser/dump.sql.gz
end=`date +%s`
dump_runtime=$((end-start))
filesize=$(stat -c%s "/home/bckuser/dump.sql.gz")
echo "pg_dumpall took ${dump_runtime} seconds. Filesize is ${filesize} bytes"

echo "Uploading dump to s3://${S3_BUCKET}${S3_PREFIX}${POSTGRES_DATABASE}.sql.gz"
start=`date +%s`
cat /home/bckuser/dump.sql.gz | aws $AWS_ARGS s3 cp - "s3://${S3_BUCKET}${S3_PREFIX}${POSTGRES_DATABASE}.sql.gz" || exit 2
end=`date +%s`
s3_runtime=$((end-start))
echo "s3 upload took ${s3_runtime} seconds"

aws $AWS_ARGS s3api put-object-tagging \
    --bucket ${S3_BUCKET} \
    --key ${S3_PREFIX}${POSTGRES_DATABASE}.sql.gz \
    --tagging '{"TagSet": [{ "Key": "dump-time", "Value": "'"$dump_runtime"'" }, { "Key": "dump-type", "Value": "postgresql" }, { "Key": "database-version", "Value": "'"$sqlver"'" }]}'

echo "SQL backup uploaded successfully"
rm -rf /home/bckuser/dump.sql.gz
