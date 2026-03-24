FROM rust:1.82-bookworm AS rust-check

RUN apt-get update && apt-get install -y curl git && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY Cargo.toml Cargo.lock ./
COPY crates/ crates/
RUN cargo check --workspace

FROM ghcr.io/foundry-rs/foundry:latest AS foundry-check

WORKDIR /app
COPY contracts/ contracts/
WORKDIR /app/contracts
RUN forge build
RUN forge test -vvv

FROM debian:bookworm-slim
COPY --from=rust-check /app/Cargo.toml /app/Cargo.toml
CMD ["echo", "autoresearch-fun build checks passed"]
