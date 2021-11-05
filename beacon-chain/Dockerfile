## BUILDER
FROM golang as builder

# Generate beacon-chain binaries
WORKDIR /usr/src/app
RUN apt update && git clone https://github.com/prysmaticlabs/prysm.git
WORKDIR /usr/src/app/prysm/cmd/beacon-chain
RUN go build -o ./tmp/beacon-chain && \
  wget -q https://github.com/eth2-clients/eth2-networks/raw/master/shared/prater/genesis.ssz -O /tmp/genesis.ssz && \
  chmod +x /usr/src/app/prysm/cmd/beacon-chain/tmp/beacon-chain

## RUNNER
FROM debian:buster-slim
 
# Copy binaries from build stage
COPY --from=builder /usr/src/app/prysm/cmd/beacon-chain/tmp/beacon-chain /usr/local/bin/beacon-chain
COPY --from=builder /tmp/genesis.ssz /genesis.ssz

RUN apt update && \
  apt install -y ca-certificates file && \
  rm -rf /var/lib/apt/lists/*

ADD ssl /ssl/

ENTRYPOINT [ "sh", "-c", "exec beacon-chain \
  --prater \
  --datadir=/data \
  --rpc-host=0.0.0.0 \
  --grpc-gateway-host=0.0.0.0 \
  --monitoring-host=0.0.0.0 \
  --http-web3provider=\"$HTTP_WEB3PROVIDER\" \
  --grpc-gateway-port=3500 \
  --grpc-gateway-corsdomain=\"$CORSDOMAIN\" \
  --genesis-state=/genesis.ssz \
  --accept-terms-of-use \
  $EXTRA_OPTS" ]
 