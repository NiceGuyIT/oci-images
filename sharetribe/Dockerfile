ARG SHARETRIBE_TAG=v9.1.0
ARG NODE_VERSION=10.15.3

# Stage 1: fetch the tagged Sharetribe source. Kept separate from the runtime
# stage so a source-only re-fetch doesn't bust the apt/node layer cache below.
FROM alpine/git:2.47.2 AS source

ARG SHARETRIBE_TAG

WORKDIR /src
RUN git clone --branch "${SHARETRIBE_TAG}" --depth 1 https://github.com/sharetribe/sharetribe.git . \
    && rm -rf .git

# Stage 2: runtime image, following upstream's own Dockerfile at this tag
# (https://github.com/sharetribe/sharetribe/blob/v9.1.0/Dockerfile), adapted
# for infra that no longer exists (see the Node.js step below).
FROM ruby:2.6.5-buster

# Buster went EOL and moved to archive.debian.org; the base image's sources
# still point at deb.debian.org, which no longer serves it.
RUN sed -i \
      -e 's|deb.debian.org/debian |archive.debian.org/debian |g' \
      -e 's|security.debian.org/debian-security|archive.debian.org/debian-security|g' \
      -e '/buster-updates/d' \
      /etc/apt/sources.list \
    && echo 'Acquire::Check-Valid-Until "false";' > /etc/apt/apt.conf.d/99no-check-valid-until

RUN apt-get update && apt-get install -y --no-install-recommends \
      lsb-release \
      wget \
      ca-certificates \
      xz-utils \
    && rm -rf /var/lib/apt/lists/*

#
# Node.js (upstream Dockerfile GPG-verified this against the SKS keyserver
# pool, which has been shut down since 2021; verify the published sha256
# checksum instead, which needs no keyserver).
#
ARG NODE_VERSION
RUN curl -fsSLO "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-x64.tar.xz" \
    && curl -fsSLO "https://nodejs.org/dist/v${NODE_VERSION}/SHASUMS256.txt" \
    && grep " node-v${NODE_VERSION}-linux-x64.tar.xz\$" SHASUMS256.txt | sha256sum -c - \
    && tar -xJf "node-v${NODE_VERSION}-linux-x64.tar.xz" -C /usr/local --strip-components=1 \
    && rm "node-v${NODE_VERSION}-linux-x64.tar.xz" SHASUMS256.txt \
    && ln -s /usr/local/bin/node /usr/local/bin/nodejs

#
# Sharetribe runtime packages: nginx (serves the maintenance page) and the
# MySQL 5.7 client libraries the mysql2 gem compiles against.
#
# Upstream installs these via the mysql-apt-config .deb, driven by
# debconf-set-selections. That package's postinst is interactive-shell-driven
# even when preseeded and, worse, its buster component is signed with a
# now-expired key (B7B3B788A8D3785C, expired 2025-10; buster is EOL so MySQL
# will never re-sign it). Skip the config package entirely and write the
# mysql-5.7 component's source line directly instead, fetched over HTTPS and
# marked explicitly trusted rather than key-verified, since the key check can
# never pass again for this frozen component.
RUN apt-get update && apt-get install -y --no-install-recommends nginx \
    && echo "deb [trusted=yes] https://repo.mysql.com/apt/debian buster mysql-5.7" > /etc/apt/sources.list.d/mysql.list \
    && apt-get update \
    && apt-get purge -y mariadb-common mysql-common || true \
    && apt-get install -y --no-install-recommends libmysqlclient-dev \
    && rm -rf /var/lib/apt/lists/*

# Matches Gemfile.lock's "BUNDLED WITH" at the pinned tag.
ENV BUNDLE_BIN=
RUN gem install bundler -v '1.17.2'

# Run as non-privileged user, matching upstream's script/entrypoint.sh
# expectations (it assumes /opt/app is writable by the running user). The
# ruby base image sets BUNDLE_PATH=/usr/local/bundle (root-owned) globally,
# which overrides --deployment's default of installing under the app
# directory, so hand that path to app too.
RUN useradd -m -s /bin/bash app \
    && mkdir -p /opt/app /opt/app/client /opt/app/log /opt/app/tmp \
    && chown -R app:app /opt/app /usr/local/bundle

WORKDIR /opt/app

# Copied once, in full, up front: upstream's own Dockerfile copies Gemfile/
# Gemfile.lock first and the rest of the tree later purely for its own layer
# caching across frequent commits. That staging doesn't help a one-shot
# fixed-tag build, and it actively breaks the mimemagic patch below (a later
# full-tree copy would overwrite the patched Gemfile/Gemfile.lock with the
# pristine ones), so copy everything once instead.
COPY --from=source --chown=app:app /src/ /opt/app/

ENV RAILS_ENV=production

USER app

# mimemagic 0.3.3 (the version this Gemfile.lock pins) was yanked from
# rubygems.org in 2021 over a bundled-database licensing dispute; 0.3.10 is
# the fixed release in the same ~> 0.3.x line both marcel and paperclip
# constrain to here. Override and relock just this gem rather than the whole
# bundle, then install from the result.
RUN echo "gem 'mimemagic', '~> 0.3.10'" >> Gemfile \
    && bundle lock --update mimemagic \
    && bundle install --deployment --without test,development

ENV NODE_ENV=production
ENV NPM_CONFIG_LOGLEVEL=error
ENV NPM_CONFIG_PRODUCTION=true

RUN npm install

EXPOSE 3000

CMD ["script/startup.sh"]
ENTRYPOINT ["script/entrypoint.sh"]

#
# Assets
#

USER root
RUN mkdir -p \
      app/assets/webpack \
      public/assets \
      public/webpack \
    && chown -R app:app \
      app/assets/javascripts \
      app/assets/webpack \
      client/app/ \
      public/assets \
      public/webpack
USER app

# config/storage.yml's `amazon:` service block reads real AWS credentials
# from APP_CONFIG (config/config_loader.rb; ENV overrides the app's own
# config/config.yml), and Rails resolves config.active_storage.service as
# part of booting the environment for assets:precompile, which eagerly
# builds an S3 client and raises if the credential fields are unset. These
# throwaway build-time-only values satisfy that check without ever reaching
# AWS (asset compilation makes no S3 calls); they are not persisted via ENV,
# so they don't leak into the running container, which gets its real
# credentials from compose-secrets.yml.
RUN aws_access_key_id=build-time-placeholder \
    aws_secret_access_key=build-time-placeholder \
    s3_region=us-east-1 \
    clp_s3_bucket_name=build-time-placeholder \
    script/prepare-assets.sh
