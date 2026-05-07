# Build Stage
FROM rustlang/rust:nightly AS builder

RUN cargo install cargo-fuzz

# Add source code to the build stage.
ADD . /grex
WORKDIR /grex

# Compile the fuzzers.
# Delete the pinned Cargo.lock so cargo regenerates it with a compatible rustix version.
RUN rm -f fuzz/Cargo.lock && cargo fuzz build

# Package Stage
FROM ubuntu:latest
COPY --from=builder /grex/fuzz/target/x86_64-unknown-linux-gnu/release/fuzz_builder /bin/fuzz_builder
