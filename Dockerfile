FROM alpine:3.15.0
LABEL maintainer="hartwig.bertrand@gmail.com"
LABEL description="Backup PostgresSQL database using pg_dumpall to S3 "

ADD install.sh install.sh
RUN sh install.sh && rm install.sh

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

ADD run.sh run.sh
ADD backup.sh backup.sh

CMD ["sh", "run.sh"]
