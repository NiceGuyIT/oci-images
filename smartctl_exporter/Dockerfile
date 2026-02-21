ARG SMARTCTL_VERSION=v0.14.0
FROM docker.io/prometheuscommunity/smartctl-exporter:${SMARTCTL_VERSION}
USER root
RUN apk add shadow
USER nobody
EXPOSE 9633
ENTRYPOINT ["/bin/smartctl_exporter"]
