FROM alpine:3.19.1
LABEL maintainer="hartwig.bertrand@gmail.com"
LABEL description="Backup PostgresSQL database using pg_dumpall to S3 "

# no HEALTHCHECK
HEALTHCHECK NONE

RUN apk update && apk upgrade 
RUN apk add postgresql-client && apk add python3 py3-pip py3-six py3-urllib3 py3-colorama curl

# install s3 tools
RUN pip install awscli
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
ENV POSTGRES_EXTRA_OPTS ''
ENV S3_ACCESS_KEY_ID **None**
ENV S3_SECRET_ACCESS_KEY **None**
ENV S3_BUCKET **None**
ENV S3_REGION us-west-1
ENV S3_PATH 'backup'
ENV S3_ENDPOINT **None**
ENV S3_S3V4 no

ENV SLACK_URL **None**
ENV ELASTIC_URL **None**
ENV BACKUP_FILENAME **None**

COPY run.sh run.sh
COPY backup.sh backup.sh

CMD ["sh", "run.sh"]
