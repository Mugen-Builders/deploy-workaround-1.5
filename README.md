# Python DApp Template

> [!WARNING]
> This repository targets **`@cartesi/cli` v1.5.x** only. It will not work correctly with earlier or later versions of the Cartesi CLI or rollups node.

This is a template for Python Cartesi DApps. It uses python3 to execute the backend application.
The application entrypoint is the `dapp.py` file.

See [DEPLOY.md](DEPLOY.md) for fly.io deployment instructions, including the workaround for the go-supervisor 5-second startup timeout present in rollups-node v1.5.
