# Build environment for the {m.txt} Linux app.
#
# Why not the official swift:* images: those are Ubuntu 24.04 (noble),
# whose libadwaita 1.5 is too old for Adwaita for Swift's generated
# bindings (AdwToggleGroup needs >= 1.7). Ubuntu 26.04 ships libadwaita
# 1.9 + GtkSourceView 5.18, but its apt swiftlang is 6.1 — too old for
# the Aparoksha packages' Swift 6.2 manifests. So: 26.04 + the swift.org
# 6.2 toolchain (the ubuntu24.04 build runs fine on 26.04).
#
#   docker build -t minimalist-linux-dev LinuxApp/dev-container
#   docker run --rm -v "$PWD:/src" -w /src/LinuxApp minimalist-linux-dev \
#     swift build --scratch-path .build-linux

FROM ubuntu:26.04
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    binutils build-essential ca-certificates curl git gnupg2 \
    libc6-dev libcurl4-openssl-dev libedit2 libpython3-dev libsqlite3-0 \
    libxml2-dev libncurses-dev libz3-dev pkg-config tzdata unzip zlib1g-dev \
    libadwaita-1-dev libgtksourceview-5-dev \
    && rm -rf /var/lib/apt/lists/*

ARG TARGETARCH
ARG SWIFT_VERSION=6.2.3
RUN set -eux; \
    case "$TARGETARCH" in \
        arm64) DIR="ubuntu2404-aarch64"; SUFFIX="-aarch64" ;; \
        amd64) DIR="ubuntu2404"; SUFFIX="" ;; \
        *) echo "unsupported arch: $TARGETARCH" >&2; exit 1 ;; \
    esac; \
    curl -fsSL "https://download.swift.org/swift-${SWIFT_VERSION}-release/${DIR}/swift-${SWIFT_VERSION}-RELEASE/swift-${SWIFT_VERSION}-RELEASE-ubuntu24.04${SUFFIX}.tar.gz" \
        | tar xz -C /opt; \
    ln -s /opt/swift-*/usr/bin/* /usr/local/bin/

# The 24.04 toolchain links libxml2.so.2; 26.04's libxml2 bumped its
# soname. The ABI surface Swift's tools use survived the bump, so a
# compat symlink bridges it.
RUN set -eux; \
    real=$(ls /usr/lib/*/libxml2.so.* | grep -E 'so\.[0-9]+$' | head -1); \
    [ -e "$(dirname "$real")/libxml2.so.2" ] || ln -s "$real" "$(dirname "$real")/libxml2.so.2"

RUN swift --version
