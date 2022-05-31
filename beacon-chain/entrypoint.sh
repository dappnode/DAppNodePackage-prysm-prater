#!/bin/bash

[[ -n $WEB3_BACKUP ]] && EXTRA_OPTS="--fallback-web3provider=${WEB3_BACKUP} ${EXTRA_OPTS}"
if [[ -n $CHECKPOINT_SYNC_URL ]]; then
  EXTRA_OPTS="--checkpoint-sync-url=${CHECKPOINT_SYNC_URL} --genesis-beacon-api-url=${CHECKPOINT_SYNC_URL}"
else
  EXTRA_OPTS="--genesis-state=/genesis.ssz"
fi

exec -c beacon-chain \
  --prater \
  --datadir=/data \
  --rpc-host=0.0.0.0 \
  --grpc-gateway-host=0.0.0.0 \
  --monitoring-host=0.0.0.0 \
  --http-web3provider=$HTTP_WEB3PROVIDER \
  --grpc-gateway-port=3500 \
  --grpc-gateway-corsdomain=$CORSDOMAIN \
  --accept-terms-of-use \
  $EXTRA_OPTS
