# Prysm DAppNode package (prater config)

[![prysm github](https://img.shields.io/badge/prysm-Github-blue.svg)](https://prylabs.net/)
[![prysm participate](https://img.shields.io/badge/prysm-participate-753a88.svg)](https://prylabs.net/participate?node=dappnode)

**Prysm prater ETH2.0 Beacon chain + validator**

Validate with prysm: a Go implementation of the Ethereum 2.0 Serenity protocol and open source project created by Prysmatic Labs. Beacon node which powers the beacon chain at the core of Ethereum 2.0

![avatar](avatar-prysm-prater.png)

Grafana dashboard thanks to the amazing work of [metanull-operator](https://github.com/metanull-operator/eth2-grafana)

|      Updated       | Champion/s |
| :----------------: | :--------: |
| :heavy_check_mark: | @tropicar  |

### Development

1. Select a Prysm branch, current work progress use to be tracked at `develop` branch. Set the branch env in the `docker-compose.dev.yml`

2. Build Prysm with the branch defined with

```
npx @dappnode/dappnodesdk build --compose_file_name=docker-compose.dev.yml
```
