ARG BUILDER_DIR=/srv/rgb

FROM rust:1.66.0-slim-bullseye as builder

RUN apt-get update \
    && apt-get -y install --no-install-recommends \
        build-essential cmake git pkg-config \
        libpq-dev libssl-dev libzmq3-dev libsqlite3-dev

ARG SRC_DIR=/usr/local/src/rgb
WORKDIR "$SRC_DIR"

ARG BUILDER_DIR
ARG VER_STORE="0.8.2"
ARG VER_NODE="0.8.4"
ARG VER_CLI="0.8.4"
ARG VER_STD="0.8.2"
ARG VER_RGB20="0.8.0"
RUN cargo install store_daemon --version "${VER_STORE}" \
        --debug --locked --all-features --root "${BUILDER_DIR}"
RUN cargo install rgb_node --version "${VER_NODE}" \
        --debug --locked --all-features --root "${BUILDER_DIR}"
RUN cargo install rgb-cli --version "${VER_CLI}" \
        --debug --locked --all-features --root "${BUILDER_DIR}"
RUN cargo install rgb20 --version "${VER_RGB20}" \
        --debug --locked --all-features --root "${BUILDER_DIR}"
RUN cargo install rgb-std \
        --git "https://github.com/RGB-WG/rgb-std" --branch "v0.8" \
        --debug --locked --all-features --root "${BUILDER_DIR}"


FROM debian:bullseye-slim

ARG DATA_DIR=/var/lib/rgb
ARG USER=rgb
ENV USER=${USER}

RUN apt-get update \
    && apt-get -y install --no-install-recommends \
       libsqlite3-0 libssl1.1 supervisor \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

RUN adduser --home "${DATA_DIR}" --shell /bin/bash --disabled-login \
        --gecos "${USER} user" ${USER}

ARG BUILDER_DIR
ARG BIN_DIR=/usr/local/bin
COPY --from=builder --chown=${USER}:${USER} \
     "${BUILDER_DIR}/bin/" "${BIN_DIR}"

COPY supervisor.conf /srv/supervisor.conf
COPY entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/entrypoint.sh

WORKDIR "${BIN_DIR}"

VOLUME "$DATA_DIR"

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
