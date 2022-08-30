FROM rust:1.63.0-slim-bullseye

RUN apt update -yqq && \
    apt install -yqq \
      cmake \
      g++ \
      libssl-dev \
      pkg-config

WORKDIR /application
