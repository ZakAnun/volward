FROM rust:1.85-bookworm AS builder
WORKDIR /app
COPY Cargo.toml Cargo.lock ./
COPY crates ./crates
COPY server ./server
RUN cargo build --release -p volward-platform-api

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl \
    && rm -rf /var/lib/apt/lists/*
COPY --from=builder /app/target/release/volward-platform-api /usr/local/bin/
COPY --from=builder /app/target/release/volward-admin /usr/local/bin/
EXPOSE 8080
CMD ["volward-platform-api"]
