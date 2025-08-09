FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get -y --quiet update && \
    apt-get --quiet -y --no-install-recommends install \
      apt-transport-https \
      bash \
      ca-certificates \
      curl \
      gnupg

SHELL ["/usr/bin/bash", "-o", "pipefail", "-c"]

RUN set -ex&& \
  DPKG_ARCH="$(dpkg --print-architecture)"; \
  export DPKG_ARCH; \
  if [ "$DPKG_ARCH" != "amd64" ] && [ "$DPKG_ARCH" != "arm64" ] && [ "$DPKG_ARCH" != "i386" ]; then \
    echo "ERROR: The architecture $DPKG_ARCH is not supported by this Dockerfile"; \
    exit 1; \
  fi; \
  export DEB_KEYRING='/usr/share/keyrings/repo.i2pd.xyz_r4sas-keyring.gpg'; \
  export DEB_LIST='/etc/apt/sources.list.d/i2pd.list'; \
  echo "deb [arch=$DPKG_ARCH signed-by=$DEB_KEYRING] https://repo.i2pd.xyz/debian bookworm main" | tee "$DEB_LIST"; \
  curl -fsSLo- https://repo.i2pd.xyz/r4sas.gpg | gpg --dearmor | tee "$DEB_KEYRING" >/dev/null

RUN apt-get -y --quiet update && \
    apt-get -y --quiet --no-install-recommends install i2pd && \
    apt-get -y clean && \
    rm -rf /var/lib/apt

RUN mkdir -vp \
      /run/i2pd \
    && \
    chown -vR i2pd:i2pd \
      /run/i2pd \
      /var/lib/i2pd \
    && \
    chmod -vR go-rwx \
      /run/i2pd \
      /var/lib/i2pd

COPY i2pd.conf /etc/i2pd/i2pd.conf

COPY monero-mainnet.conf /etc/i2pd/tunnels.conf.d/monero-mainnet.conf

EXPOSE 58618

USER i2pd

ENTRYPOINT ["i2pd", "--conf=/etc/i2pd/i2pd.conf", "--tunconf=/etc/i2pd/tunnels.conf", "--tunnelsdir=/etc/i2pd/tunnels.conf.d", "--pidfile=/run/i2pd/i2pd.pid", "--service"]
