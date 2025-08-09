# containerized-monero-node

Spin up a Monero node with Tor and I2P hidden service support using Docker.


## About

I created this project as a solution for running your own Monero node in light
of [recent developments in Monero OpSec best practices][2], as I felt current
solutions were lacking in their considerations for security and design. CMN
provides a (more) hardened, light(er)weight solution for spinning up your
own Monero node to avoid feds, skids, and YouTubers analyzing your time on the
Monero blockchain. I have also designed this project with extensibility in
mind, and provide quite a few configuration options for individuals wanting to
spin up a Monero node.

This project is based upon the work of [lalanza808/docker-monero-node][1]


## Usage

### Quickstart

The simplest way to use this project is as follows:

1. Clone the repository
2. Copy `env.example` to `.env` and edit it. The defaults should work fine.
3. Copy `compose.example.yaml` to `compose.yaml`. This shouldn't require edits.
4. Run `docker compose build` to build the images.
5. Run `docker compose up --detach` to start your node.
6. ???
7. Profit!

To view node status, you can run `docker compose logs --no-log-prefix monerod`.


## Configuration

The bulk of configuration for this project should be possible via the `.env.`
file. You can also edit `compose.yaml` if you understand what you're doing.

### Advanced configuration

90% of configuration for the included services is done via their config files
in their respective directories under `dockerfiles`. These include:

- `dockerfiles/monerod/bitmonero.conf`
- `dockerfiles/tor/torrc`
- `dockerfiles/i2pd/i2pd.conf`

You can edit these files and run `docker compose build` to re-build the images
to apply any changes.

### Default Ports

| **Service** | **Port** | **Scope**       | **Description**        | **Notes**                                                                                           |
|-------------|----------|-----------------|------------------------|-----------------------------------------------------------------------------------------------------|
| monerod     | 18080    | **global**      | P2P Network            | Default for Monero nodes.                                                                           |
| monerod     | 18089    | **global**      | Restricted  JSON-RPC   | Change to host machine in `compose.yaml` if you wish to only expose your node over hidden services. |
| i2pd        | 58618    | **global**      | I2P listen port        | Hardcoded I2PD listen port this for server environments.                                            |
| monerod     | 18081    | compose network | Unrestricted JSON-RPC  | Default for Monero nodes.                                                                           |
| i2pd        | 4447     | compose network | I2PD SOCKS5 proxy      | Used for Monero's tx-proxy over the I2P network.                                                    |
| tor         | 9050     | compose network | Tor SOCKS5 proxy       | Used for Monero's tx-proxy over the Tor network.                                                    |
| monerod     | 18084    | tor network     | P2P Network (over Tor) | Forwarded over the Tor network by the Tor client.                                                   |
| monerod     | 18085    | i2p network     | P2P (over I2P)         | Forwarded over the I2P network by I2PD.                                                             |

#### Notes:

- Docker Compose will open ports in your firewall for **global** ports by default.
- 'compose network' ports are available to all services in `compose.yaml`
- tor/i2p network ports are managed by tor/i2pd. You don't need to forward anything.


## Design Decisions

### Security

I have taken several precautions for securing containers and data in the
design of this project. These include:

#### Docker

- As few ports are forwarded from containers to the host machine as possible.
- Git commit and tag PGP signatures are checked during the monerod build step.
- Only a few `EXPOSE` directives are used across Dockerfiles.
  - See comments about why `EXPOSE 9050` is disabled in the Tor Dockerfile.
- Where possible (Tor, PurpleI2P), packages are installed from official repos.
- Docker images are built locally rather than pulled from external sources.

#### monerod

- ZMQ messaging is disabled as the [official Monero docs][3] recommend.
- Transaction padding is enabled by default to prevent traffic analysis.
- Cloudflare's `1.1.1.1` DNS resolver is used in order to parse DNSSEC records.
  - This is important for features like `enforce-dns-checkpointing` to work.
  - I tried several better resolvers (LibreOps, OpenNIC), but none worked.
  - If you are aware of a better libre resolver, please open a pull request!
- The peer ban list from [Boog900/monero-ban-list][4] is used by default.
- The global peer ban list is enabled by default (`--enable-dns-blocklist`)
- DNS checkpointing is enabled by default (`--enforce-dns-checkpointing`)


## TODO

- [ ] Create functionality for backing up named volumes [example][6]
- [ ] Improve functionality for testing hidden service availability
- [ ] Add feature to automatically publish nodes to [monero.fail][5]
- [ ] Add functionality for publishing under a clearnet domain with CORS
- [ ] Add functionality for using a "vanity" I2P URL via reg.i2p

[1]: https://github.com/lalanza808/docker-monero-node
[2]: https://monero.fail/opsec
[3]: https://docs.getmonero.org/interacting/monerod-reference/?h=zmq#node-rpc-api
[4]: https://github.com/Boog900/monero-ban-list
[5]: https://monero.fail
[6]: https://blog.burkeware.com/2020/04/10/backup-and-restore-docker-compose-named-volumes/
