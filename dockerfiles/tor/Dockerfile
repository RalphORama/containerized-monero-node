FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get -y --quiet update && \
    apt-get -y --quiet --no-install-recommends install \
      apt-transport-https \
      bash \
      ca-certificates \
      curl \
      gnupg \
      grep

SHELL ["/usr/bin/bash", "-o", "pipefail", "-c"]

# Install Tor from Tor's package repository
# https://support.torproject.org/apt/#apt_tor-deb-repo
RUN set -ex && \
  DPKG_ARCH="$(dpkg --print-architecture)"; \
  export DPKG_ARCH; \
  if [ "$DPKG_ARCH" != "amd64" ] && [ "$DPKG_ARCH" != "arm64" ] && [ "$DPKG_ARCH" != "i386" ]; then \
    echo "ERROR: The architecture $DPKG_ARCH is not supported by this Dockerfile"; \
    exit 1; \
  fi; \
  export DEB_KEYRING='/usr/share/keyrings/deb.torproject.org-keyring.gpg'; \
  export DEB_LIST='/etc/apt/sources.list.d/tor.list'; \
  export DEB_URL='https://deb.torproject.org/torproject.org'; \
  echo "deb [arch=$DPKG_ARCH signed-by=$DEB_KEYRING] $DEB_URL bookworm main" | tee "$DEB_LIST"; \
  curl -fsSLo- "$DEB_URL/A3C4F0F979CAA22CDBA8F512EE8CBC9E886DDD89.asc" | gpg --dearmor | tee "$DEB_KEYRING" >/dev/null

RUN apt-get -y --quiet update && \
    apt-get -y --quiet --no-install-recommends install tor && \
    apt-get -y clean && \
    rm -rf /var/lib/apt

RUN mkdir -vp \
      /run/tor \
      /var/lib/tor/monerod \
    && \
    chown -vR debian-tor:debian-tor \
      /run/tor \
      /var/lib/tor/monerod \
    && \
    chmod -vR go-rwx \
      /run/tor \
      /var/lib/tor/monerod

COPY torrc /etc/tor/torrc

HEALTHCHECK \
  --interval=300s \
  --timeout=15s \
  --start-period=120s \
  --start-interval=10s \
  CMD curl -fsSL -x socks5h://127.0.0.1:9050 'https://check.torproject.org/api/ip' | grep -q -E '"IsTor"\s*:\s*true' || exit 1

# Docker docs say "The EXPOSE instruction doesn't actually publish the port."
# However, if we add this instruction, docker compose will publish the port.
# Which is bad!! IDK how to make compose not do that so... just comment it out.
# /shrug
#EXPOSE 9050

USER debian-tor

CMD ["tor"]
