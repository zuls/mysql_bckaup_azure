
FROM ubuntu:latest

ENV DEBIAN_FRONTEND noninteractive

RUN apt-get update -y -q && \
  apt-get install -y mysql-client-5.7 nodejs-legacy curl wget npm bash python-pip samba-client && \
  apt-get clean && \
  rm -rf /var/lib/apt/lists/* && \
    touch /etc/samba/smb.conf && \
    pip install awscli

RUN npm install -g n azure-cli
RUN n 0.12.7

RUN mkdir -p /backup
ADD . /backup
RUN chmod 0755 /backup/*

ENTRYPOINT ["/backup/take_mysql_dump.sh"]

