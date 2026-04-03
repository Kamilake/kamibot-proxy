# Multi-architecture build support (amd64 + arm64)
# For amd64: uses SIMD optimizations (AVX2/SSE4.2) with TARGET_CPU tuning
# For arm64: uses SIMD optimizations (NEON)
ARG TARGET_CPU="haswell"

FROM docker.io/library/alpine:edge AS builder
ARG TARGET_CPU
ARG TARGETARCH

# Set Rust target and flags based on architecture
RUN if [ "$TARGETARCH" = "arm64" ]; then \
        echo "aarch64-unknown-linux-musl" > /tmp/rust_target; \
        echo "-Lnative=/usr/lib" > /tmp/rustflags; \
    else \
        echo "x86_64-unknown-linux-musl" > /tmp/rust_target; \
        echo "-Lnative=/usr/lib -C target-cpu=${TARGET_CPU}" > /tmp/rustflags; \
    fi

ENV RUSTFLAGS_FILE="/tmp/rustflags"

RUN apk upgrade && \
    apk add curl gcc g++ musl-dev cmake make && \
    curl -sSf https://sh.rustup.rs | sh -s -- --profile minimal --component rust-src --default-toolchain nightly-2025-06-12 -y

WORKDIR /build

COPY Cargo.toml Cargo.lock ./
COPY .cargo ./.cargo/

RUN mkdir src/
RUN echo 'fn main() {}' > ./src/main.rs
RUN export RUST_TARGET=$(cat /tmp/rust_target) && \
    export RUSTFLAGS=$(cat /tmp/rustflags) && \
    source $HOME/.cargo/env && \
    if [ "$TARGET_CPU" = "x86-64" ]; then \
        cargo build --release --target="$RUST_TARGET" --no-default-features --features no-simd; \
    else \
        cargo build --release --target="$RUST_TARGET"; \
    fi

RUN rm -f target/*/release/deps/gateway_proxy*
COPY ./src ./src

RUN export RUST_TARGET=$(cat /tmp/rust_target) && \
    export RUSTFLAGS=$(cat /tmp/rustflags) && \
    source $HOME/.cargo/env && \
    if [ "$TARGET_CPU" = "x86-64" ]; then \
        cargo build --release --target="$RUST_TARGET" --no-default-features --features no-simd; \
    else \
        cargo build --release --target="$RUST_TARGET"; \
    fi && \
    cp target/$RUST_TARGET/release/gateway-proxy /gateway-proxy && \
    strip /gateway-proxy

FROM docker.io/library/alpine:edge

RUN apk add --no-cache \
    tini \
    busybox-extras \
    curl \
    wget \
    bind-tools \
    net-tools \
    iproute2 \
    iputils \
    tcpdump \
    strace \
    ltrace \
    lsof \
    htop \
    procps \
    jq \
    vim \
    less \
    file \
    gdb

COPY --from=builder /gateway-proxy /gateway-proxy

ENTRYPOINT ["/sbin/tini", "--"]
CMD ["./gateway-proxy"]
