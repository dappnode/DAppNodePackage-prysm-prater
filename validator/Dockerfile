## BUILDER
FROM golang as builder

# Generate validator binaries
WORKDIR /usr/src/app
RUN apt update && git clone https://github.com/prysmaticlabs/prysm.git
WORKDIR /usr/src/app/prysm/cmd/validator
RUN go build -o ./tmp/validator && chmod +x /usr/src/app/prysm/cmd/validator/tmp/validator

## RUNNER
FROM debian:buster-slim

RUN apt update && \
  apt install -y file git curl && \
  rm -rf /var/lib/apt/lists/*

# Copy binaries from build stage
COPY --from=builder /usr/src/app/prysm/cmd/validator/tmp/validator /usr/local/bin

# Copy entrypoint script
COPY entrypoint.sh /usr/local/bin

ENTRYPOINT [ "/usr/local/bin/entrypoint.sh" ]
