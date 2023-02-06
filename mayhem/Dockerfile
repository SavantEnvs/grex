# Build Stage
FROM ghcr.io/evanrichter/cargo-fuzz:latest AS builder

# Add source code to the build stage.
ADD . /grex
WORKDIR /grex

# Compile the fuzzers.
RUN cargo fuzz build

# Package Stage
FROM ubuntu:latest
COPY --from=builder /grex/fuzz/target/x86_64-unknown-linux-gnu/release/fuzz_builder /bin/fuzz_builder
