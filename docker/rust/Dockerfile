FROM rust:1.80.0-slim-bookworm

RUN apt update -yqq && \
    apt install -yqq \
      cmake \
      g++ \
      libssl-dev \
      pkg-config

WORKDIR /application
