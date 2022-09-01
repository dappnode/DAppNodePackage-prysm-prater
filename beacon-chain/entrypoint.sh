#!/bin/bash

if [[ -n $WEB3_BACKUP ]] && [[ $EXTRA_OPTS != *"--fallback-web3provider"* ]]; then
  EXTRA_OPTS="--fallback-web3provider=${WEB3_BACKUP} ${EXTRA_OPTS}"
fi

if [[ -n $CHECKPOINT_SYNC_URL ]]; then
  EXTRA_OPTS="--checkpoint-sync-url=${CHECKPOINT_SYNC_URL} --genesis-beacon-api-url=${CHECKPOINT_SYNC_URL} ${EXTRA_OPTS}"
else
  EXTRA_OPTS="--genesis-state=/genesis.ssz ${EXTRA_OPTS}"
fi

case $_DAPPNODE_GLOBAL_EXECUTION_CLIENT_PRATER in
"goerli-geth.dnp.dappnode.eth")
  HTTP_ENGINE="http://goerli-geth.dappnode:8551"
  ;;
"goerli-nethermind.dnp.dappnode.eth")
  HTTP_ENGINE="http://goerli-nethermind.dappnode:8551"
  ;;
"goerli-erigon.dnp.dappnode.eth")
  HTTP_ENGINE="http://goerli-erigon.dappnode:8551"
  ;;
*)
  echo "Unknown value for _DAPPNODE_GLOBAL_EXECUTION_CLIENT_PRATER: $_DAPPNODE_GLOBAL_EXECUTION_CLIENT_PRATER"
  HTTP_ENGINE=_DAPPNODE_GLOBAL_EXECUTION_CLIENT_PRATER
  ;;
esac

# MEVBOOST: https://hackmd.io/@prysmaticlabs/BJeinxFsq
if [ -n "$_DAPPNODE_GLOBAL_MEVBOOST_PRATER" ] && [ "$_DAPPNODE_GLOBAL_MEVBOOST_PRATER" == "true" ]; then
  echo "MEVBOOST is enabled"
  EXTRA_OPTS="--http-mev-relay=http://mev-boost.mev-boost-goerli.dappnode:18550 ${EXTRA_OPTS}"
fi

exec -c beacon-chain \
  --datadir=/data \
  --rpc-host=0.0.0.0 \
  --accept-terms-of-use \
  --prater \
  --grpc-gateway-host=0.0.0.0 \
  --monitoring-host=0.0.0.0 \
  --p2p-tcp-port=$P2P_TCP_PORT \
  --p2p-udp-port=$P2P_UDP_PORT \
  --http-web3provider=$HTTP_ENGINE \
  --grpc-gateway-port=3500 \
  --grpc-gateway-corsdomain=$CORSDOMAIN \
  --jwt-secret=/jwtsecret \
  $EXTRA_OPTS
