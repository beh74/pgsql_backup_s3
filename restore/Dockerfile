FROM alpine:3.19.1
LABEL maintainer="hartwig.bertrand@gmail.com"
LABEL description="Backup PostgresSQL database using pg_dumpall to S3 "

# no HEALTHCHECK
HEALTHCHECK NONE

RUN apk update && apk upgrade 
RUN apk add postgresql-client && apk add python3 py3-pip py3-six py3-urllib3 py3-colorama curl

# install s3 tools
RUN pip install awscli --break-system-packages
RUN apk del py3-pip

# cleanup
RUN apk cache clean && rm -rf /var/cache/apk/*

# Create a group and user to perform backup
RUN addgroup -S bckgrp && adduser -S bckuser -G bckgrp -h /home/bckuser
USER bckuser

ENV POSTGRES_DATABASE **None**
ENV POSTGRES_HOST **None**
ENV POSTGRES_PORT 5432
ENV POSTGRES_USER **None**
ENV POSTGRES_PASSWORD **None**
ENV S3_ACCESS_KEY_ID **None**
ENV S3_SECRET_ACCESS_KEY **None**
ENV S3_BUCKET **None**
ENV S3_REGION us-west-1
ENV S3_PATH 'backup'
ENV DROP_PUBLIC 'no'
ENV S3_ENDPOINT **None**
ENV S3_OBJECT **None**

ENV RESTORE_OPERATION list
ENV RESTORE_VERSION **None** 

COPY restore.sh restore.sh

CMD ["sh", "restore.sh"]
