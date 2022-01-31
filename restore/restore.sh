#! /bin/sh

set -eo pipefail
set -o pipefail

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

if [ "${S3_OBJECT}" = "**None**" ]; then
  echo "You need to set the S3_OBJECT environment variable."
  exit 1
fi

if [ "${POSTGRES_DATABASE}" = "**None**" ]; then
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


# env vars needed for aws tools
export AWS_ACCESS_KEY_ID=$S3_ACCESS_KEY_ID
export AWS_SECRET_ACCESS_KEY=$S3_SECRET_ACCESS_KEY
export AWS_DEFAULT_REGION=$S3_REGION

export PGPASSWORD=$POSTGRES_PASSWORD
POSTGRES_HOST_OPTS="-h $POSTGRES_HOST -p $POSTGRES_PORT -U $POSTGRES_USER"

if [ "${S3_ENDPOINT}" == "**None**" ]; then
  AWS_ARGS=""
else
  AWS_ARGS="--endpoint-url ${S3_ENDPOINT}"
fi

echo "List object versions from S3"
aws $AWS_ARGS s3 ls s3://$S3_BUCKET/$S3_PREFIX/

if [ "${RESTORE_OPERATION}" = "list" ]; then
  echo "List object versions from S3 :"  
  aws $AWS_ARGS s3api list-object-versions --bucket $S3_BUCKET --prefix $S3_PREFIX/${S3_OBJECT} | jq -r '.Versions[] | "\(.VersionId)\t\(.LastModified)\t\(.Size)\t\(.IsLatest)"' 
  return 0
elif [ "${RESTORE_OPERATION}" = "info" ]; then
  if [ "${RESTORE_VERSION}" == "**None**" ]; then
    echo "You need to set the RESTORE_VERSION environment variable."
    exit 1
  fi
  echo "This object' tags are the following :"
  aws $AWS_ARGS s3api get-object-tagging --bucket $S3_BUCKET --key $S3_PREFIX/${S3_OBJECT}  --version-id $RESTORE_VERSION | jq -r '.TagSet[] | "\(.Key)\t\t\(.Value)"' 
  return 0
elif [ "${RESTORE_OPERATION}" = "restore" ]; then
  if [ "${RESTORE_VERSION}" == "**None**" ]; then
    echo "You need to set the RESTORE_VERSION environment variable."
    exit 1
  fi
  echo "Launching restore operation for object version ${RESTORE_VERSION} ..."
  echo "Step 1 : geting object version from S3 ..."
  aws $AWS_ARGS s3api get-object --bucket $S3_BUCKET --key $S3_PREFIX/${S3_OBJECT}  --version-id $RESTORE_VERSION dump.sql.gz
  echo "  Done !"

  echo "Step 2 : unziping sql dump ..."
  gzip -d dump.sql.gz
  echo "  Done !"

  echo "Step 3 : restoring database ..."
  if [ "${DROP_PUBLIC}" == "yes" ]; then
	  echo "Recreating the public schema"
	  psql $POSTGRES_HOST_OPTS -d $POSTGRES_DATABASE -c "drop schema public cascade; create schema public;"
  fi
  psql $POSTGRES_HOST_OPTS -d $POSTGRES_DATABASE < dump.sql

  rm dump.sql
else
  echo "Unknown RESTORE_OPERATION value. It should be :"
  echo "- list : to list object versions"
  echo "- info : to get object versions tags"
  echo "- restore : to restore the database"
fi
return 0

echo "Restore complete"

