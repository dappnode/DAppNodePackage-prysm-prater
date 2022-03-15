FROM debian:buster-slim as binary

ARG TARGETARCH
ARG UPSTREAM_VERSION
ENV DOWNLOAD_URL https://github.com/prysmaticlabs/prysm/releases/download

RUN DEBIAN_FRONTEND=noninteractive \
  apt update && apt install --assume-yes --no-install-recommends wget ca-certificates && \
  wget -q $DOWNLOAD_URL/$UPSTREAM_VERSION/validator-$UPSTREAM_VERSION-linux-${TARGETARCH:-amd64} -O /usr/local/bin/validator && \
  chmod +x  /usr/local/bin/validator

FROM debian:buster-slim

RUN apt update && \
  apt install -y ca-certificates file git curl cron jq unzip supervisor && \
  rm -rf /var/lib/apt/lists/*

#Copy binaries from build stage
COPY --from=binary /usr/local/bin/validator /usr/local/bin

# Setup cronjob
COPY get-keys-cron /etc/cron.d/
COPY get-keys.sh /usr/local/bin/get-keys.sh
# Apply cron job
RUN crontab /etc/cron.d/get-keys-cron

# Copy migration script
COPY eth2-migrate.sh /usr/local/bin

# Copy entrypoint script
COPY entrypoint.sh /usr/local/bin

# Copy supervisor config
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf

ENTRYPOINT [ "/usr/local/bin/entrypoint.sh" ]
