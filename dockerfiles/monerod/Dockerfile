FROM debian:bookworm-slim AS builder

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get -y update && \
    apt-get -y --no-install-recommends install \
      bash \
      ca-certificates \
      curl \
      git \
      gnupg \
      build-essential cmake pkg-config libboost-all-dev libssl-dev \
      libzmq3-dev libunbound-dev libsodium-dev

SHELL ["/usr/bin/bash", "-o", "pipefail", "-c"]

WORKDIR /src/monero

ARG MONERO_RELEASE v0.18.4.1

RUN git clone \
      --recursive \
      --depth=1 \
      --branch=$MONERO_RELEASE \
      https://github.com/monero-project/monero \
      .

# Import PGP keys and verify commits/tags
# TODO: Check emails attached to keys against commit/tag?
RUN set -ex && \
    export GIT_COMMIT_KEYSIG="$(git --no-pager show -s --show-signature 2>&1 | grep --color=never -oE '[0-9A-Z]{40}')"; \
    export GIT_TAG_KEYSIG="$(git --no-pager tag -v $MONERO_RELEASE 2>&1 | grep --color=never -oE '[0-9A-Z]{40}')"; \
    if [ -z "$GIT_COMMIT_KEYSIG" ] || [ -z "$GIT_TAG_KEYSIG" ]; then \
      echo "ERROR: GIT_COMMIT_KEYSIG or GIT_TAG_KEYSIG is undefined!"; \
      exit 1; \
    fi \
    && \
    gpg --keyserver 'keyserver.ubuntu.com' \
      --recv-keys "$GIT_COMMIT_KEYSIG" "$GIT_TAG_KEYSIG" \
    && \
    git verify-commit --verbose HEAD && \
    git verify-tag --verbose $MONERO_RELEASE

RUN git submodule init && \
    git submodule update

ARG MAKE_THREADS 2

RUN make -j$MAKE_THREADS


FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

SHELL ["/usr/bin/bash", "-o", "pipefail", "-c"]

RUN apt-get -y update && \
    apt-get -y --no-install-recommends install \
      bash \
      ca-certificates \
      curl \
      grep \
      'libboost-chrono1.74.0' \
      'libboost-filesystem1.74.0' \
      'libboost-program-options1.74.0' \
      'libboost-regex1.74.0-icu72' \
      'libboost-serialization1.74.0' \
      'libboost-thread1.74.0' \
      'libc6' \
      'libgcc-s1' \
      'libminiupnpc17' \
      'librandomx0' \
      'libsodium23' \
      'libssl3' \
      'libstdc++6' \
      'libunbound8' \
      'libzmq5' \
    && \
    apt-get -y clean && \
    rm -rf /var/lib/apt

COPY --from=builder /src/monero/build/Linux/_no_branch_/release/bin /usr/local/bin/

COPY entrypoint.sh /entrypoint.sh

COPY test_hidden_services.sh /test_hidden_services.sh

RUN mkdir -vp /monero

COPY bitmonero.conf /monero/bitmonero.conf

RUN curl -fsSLo /monero/ban_list.txt \
    https://raw.githubusercontent.com/Boog900/monero-ban-list/refs/heads/main/ban_list.txt

VOLUME ["/monero/lmdb"]

# P2P Network
EXPOSE 18080
# Unrestricted JSON-RPC
EXPOSE 18081
# Restricted JSON-RPC
EXPOSE 18089

# ZMQ RPC (unused)
#EXPOSE 18082
# ZMQ Pub (unused)
#EXPOSE 18083
# Wallet RPC (unused)
#EXPOSE 18088

ENTRYPOINT ["/entrypoint.sh"]
