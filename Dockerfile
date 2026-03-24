# Pin images by digest for reproducible, supply-chain-safe builds.
FROM rust:1.85-bookworm@sha256:e51d0265072d2d9d5d320f6a44dde6b9ef13653b035098febd68cce8fa7c0bc4 AS rust-check

RUN apt-get update && apt-get install -y curl git && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY Cargo.toml Cargo.lock ./
COPY crates/ crates/
RUN cargo check --workspace

FROM ghcr.io/foundry-rs/foundry:latest@sha256:9e591221051112fe0bb530abcaba67f43f01ebbd12a94a8632d570d5e065a8bf AS foundry-check

WORKDIR /app
COPY contracts/ contracts/
WORKDIR /app/contracts
RUN forge build
RUN forge test -vvv

FROM debian:bookworm-slim
COPY --from=rust-check /app/Cargo.toml /app/Cargo.toml
CMD ["echo", "autoresearch-fun build checks passed"]
