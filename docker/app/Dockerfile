FROM ubuntu:22.04

# prevent timezone dialogue
ENV DEBIAN_FRONTEND=noninteractive

RUN apt update && \
    apt upgrade -y
RUN apt install -y \
        gcc \
        xz-utils \
        ca-certificates \
        vim \
        curl \
        git \
        make

RUN git config --global --add safe.directory /application
# nim
RUN curl https://nim-lang.org/choosenim/init.sh -sSf | sh -s -- -y
ENV PATH /root/.nimble/bin:$PATH
RUN nimble install -y nimlangserver --accept -l
# rust
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
