# blimp-relay — App Store Connect webhook receiver

FROM swift:6.1-noble AS builder

WORKDIR /build
COPY Package.swift Package.resolved ./
COPY Sources ./Sources
COPY Tests ./Tests

RUN swift build -c release --product blimp-relay

FROM swift:6.1-noble-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /build/.build/release/blimp-relay /usr/local/bin/blimp-relay

EXPOSE 13100

ENTRYPOINT ["/usr/local/bin/blimp-relay"]
