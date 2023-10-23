#! /bin/sh

set -e

export STATUS="KO"

function notify {
  if [ "${STATUS}" = "KO" ]; then
     echo "Backup failed for :"
  else
     echo "Backup is successfull for :"
  fi
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
    if [ "${STATUS}" = "KO" ]; then
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
  fi

  if [ "${ELASTIC_URL}" = "**None**" ]; then
    echo "Elasticsearch URL not provided"
  else
    if [ "${STATUS}" = "KO" ]; then
      echo "Sending data to elasticsearch"
      ts=$(date -u +"%Y-%m-%dT%T")
      payload='
      {
      "database.type": "postgresql",
      "database.name": "'"${POSTGRES_DATABASE}"'",
      "database.host": "'"${POSTGRES_HOST}"'",
      "database.port": "'"${POSTGRES_PORT}"'",
      "database.user": "'"${POSTGRES_USER}"'",
      "dump.status": "failed",
      "s3.bucket": "'"${S3_BUCKET}"'",
      "s3.prefix": "'"${S3_PREFIX}"'",
      "s3.endpoint": "'"${S3_ENDPOINT}"'",
      "agent.hostname": "'"{$HOSTNAME}"'",
      "@timestamp": "'"${ts}"'"
      }'
      curl -s -X POST -H "Content-type: application/json" -d "$payload" $ELASTIC_URL
   fi
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

if [ "${BACKUP_FILENAME}" = "**None**" ]; then
  BACKUP_FILENAME=$POSTGRES_DATABASE
fi

if [ "${POSTGRES_USER}" = "**None**" ]; then
  echo "You need to set the POSTGRES_USER environment variable."
  exit 1
fi

if [ "${POSTGRES_PASSWORD}" = "**None**" ]; then
  echo "You need to set the POSTGRES_PASSWORD environment variable or link to a container named POSTGRES."
  exit 1
fi

if [ "${S3_ENDPOINT}" = "**None**" ]; then
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
  S3_PREFIX="${S3_PREFIX}/"  
fi

rm -rf /home/bckuser/${BACKUP_FILENAME}.tar
rm -rf /home/bckuser/${BACKUP_FILENAME}

echo "Connecting PostgreSql server to get the server version"
sqlver=`psql -t -h $POSTGRES_HOST -p $POSTGRES_PORT -U $POSTGRES_USER -d $POSTGRES_DATABASE -c "SHOW server_version;"`

# get database size in bytes
dbsize=`psql -t -h $POSTGRES_HOST -p $POSTGRES_PORT -U $POSTGRES_USER -d $POSTGRES_DATABASE -c "select pg_size_pretty(pg_database_size('${POSTGRES_DATABASE}'));"`

echo "Creating dump of all databases from ${POSTGRES_HOST} version ${sqlver}..."
start=`date +%s`
#pg_dumpall -h $POSTGRES_HOST -p $POSTGRES_PORT -U $POSTGRES_USER | gzip > /home/bckuser/dump.sql.gz
pg_dump -h $POSTGRES_HOST -p $POSTGRES_PORT -U $POSTGRES_USER -d $POSTGRES_DATABASE -v -C -Z 6 -F d -j 4 -b -f  /home/bckuser/$BACKUP_FILENAME
# create a tar file for $POSTGRES_DATABASE folder
tar -cvf "/home/bckuser/${BACKUP_FILENAME}.tar" "/home/bckuser/${BACKUP_FILENAME}"
end=`date +%s`
dump_runtime=$((end-start))
filesize=$(stat -c%s "/home/bckuser/${BACKUP_FILENAME}.tar")
echo "pg_dumpall took ${dump_runtime} seconds. Filesize is ${filesize} bytes"

echo "Uploading dump to s3://${S3_BUCKET}/${S3_PREFIX}${BACKUP_FILENAME}.tar"
start=`date +%s`
cat /home/bckuser/${BACKUP_FILENAME}.tar | aws $AWS_ARGS s3 cp - "s3://${S3_BUCKET}/${S3_PREFIX}${BACKUP_FILENAME}.tar" || exit 2
end=`date +%s`
s3_runtime=$((end-start))
echo "s3 upload took ${s3_runtime} seconds"

aws $AWS_ARGS s3api put-object-tagging \
    --bucket ${S3_BUCKET} \
    --key "${S3_PREFIX}${BACKUP_FILENAME}.tar" \
    --tagging '{"TagSet": [{ "Key": "dump-time", "Value": "'"$dump_runtime"'" }, { "Key": "dump-type", "Value": "postgresql" }, { "Key": "database-version", "Value": "'"$sqlver"'" }]}'

echo "SQL backup uploaded successfully"
rm -rf /home/bckuser/${BACKUP_FILENAME}.tar
rm -rf /home/bckuser/${BACKUP_FILENAME}

if [ "${ELASTIC_URL}" = "**None**" ]; then
    echo "Elasticsearch URL not provided"
    export STATUS="OK"
else
    echo "Sending data to elasticsearch"
    ts=$(date -u +"%Y-%m-%dT%T")

    payload='
    {
    "database.type": "postgresql",
    "database.version": "'"$sqlver"'",
    "database.name": "'"${POSTGRES_DATABASE}"'",
    "database.host": "'"${POSTGRES_HOST}"'",
    "database.port": "'"${POSTGRES_PORT}"'",
    "database.user": "'"${POSTGRES_USER}"'",
    "database.dbsize": "'$dbsize'",
    "dump.duration": '"$dump_runtime"',
    "dump.filesize": '"$filesize"',
    "dump.status": "successfull",
    "dump.filename": "'"${BACKUP_FILENAME}.tar"'",
    "s3.bucket": "'"${S3_BUCKET}"'",
    "s3.prefix": "'"${S3_PREFIX}"'",
    "s3.endpoint": "'"${S3_ENDPOINT}"'",
    "s3.duration": '"$s3_runtime"',
    "agent.hostname": "'"$HOSTNAME"'",
    "@timestamp": "'"${ts}"'"
    }'
    curl -s -X POST -H "Content-type: application/json" -d "$payload" $ELASTIC_URL

    export STATUS="OK"

fi
