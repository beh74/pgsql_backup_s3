#! /bin/sh

# exit if a command fails
set -eo pipefail

apk update

# install pg_dump
apk add postgresql-client

# install s3 tools
apk add python3 py3-pip py3-six py3-urllib3 py3-colorama curl
pip install awscli
apk del py3-pip

# cleanup
rm -rf /var/cache/apk/*
