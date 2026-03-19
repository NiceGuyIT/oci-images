ARG COREDNS_VERSION=v1.14.2

# Stage 1: Build CoreDNS with the alias plugin
FROM golang:1.24-alpine AS builder

ARG COREDNS_VERSION
ARG ALIAS_PLUGIN_MODULE=github.com/serverwentdown/alias

RUN apk add --no-cache git make

WORKDIR /src

# Clone CoreDNS source at the specified version
RUN git clone --branch ${COREDNS_VERSION} --depth 1 https://github.com/coredns/coredns.git .

# Insert the alias plugin into plugin.cfg (after the file plugin, since alias works with file/auto)
RUN sed -i '/^file:file/a alias:'"${ALIAS_PLUGIN_MODULE}"'' plugin.cfg

# Generate and build
RUN go generate && make

# Stage 2: Minimal runtime image
FROM alpine:3

RUN apk add --no-cache ca-certificates

COPY --from=builder /src/coredns /usr/local/bin/coredns

EXPOSE 53 53/udp

ENTRYPOINT ["/usr/local/bin/coredns"]
