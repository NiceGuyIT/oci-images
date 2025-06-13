ARG ARCH="amd64"
ARG OS="linux"
FROM prometheuscommunity/smartctl-exporter
LABEL maintainer="The Prometheus Authors <prometheus-developers@googlegroups.com>"

#RUN apk add smartmontools shadow
USER root
RUN apk add shadow

# Change the group ID (gid) of the disk group to match the host's disk group
#RUN groupmod --gid 490 disk

#ARG ARCH="amd64"
#ARG OS="linux"
#COPY .build/${OS}-${ARCH}/smartctl_exporter /bin/smartctl_exporter

EXPOSE      9633
USER        nobody
#USER        root
ENTRYPOINT  [ "/bin/smartctl_exporter" ]
