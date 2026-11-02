# This is a multi-stage build.
#
# Use --target to choose which image to build:
# docker build --tag otfd --target otfd .
# docker build --tag otf-agent --target otf-agent .
# docker build --tag otf-job --target otf-job .

# STAGE: base
# This stage contains the files/packages that are used by the final images.
FROM alpine:3.23.3 AS base

# Build cache optimization: use cache mounts
# https://docs.docker.com/build/cache/optimize/#use-cache-mounts Mounting
# /etc/apk/cache with type=cache lets the image build system handle apk's cache
# for us, without leaving any cache files in the image itself.

# To Do:
#   - Update base image after CVEs are fixed
#   - Remove apk update && apk upgrade (When the CVEs are fixed, this is no longer relevant)
RUN --mount=type=cache,target=/etc/apk/cache \
  apk update && \
  apk upgrade --no-cache && \
  apk add --no-cache --upgrade git gcompat openssh-client

# Create non-root user and group, which will be used in the final image. We
# can't switch to it now, because the change only lasts until the end of the
# stage. The final images refer to it by number: Kubernetes can only verify
# runAsNonRoot against a numeric user.
RUN adduser -D -u 4096 otf

ARG TARGETPLATFORM

# STAGE: otfd
# Final stage that takes the `base` stage and the `otfd` binary
FROM base AS otfd
COPY $TARGETPLATFORM/otfd /usr/local/bin/
USER 4096:4096
ENTRYPOINT ["/usr/local/bin/otfd"]

# STAGE: otf-agent
# Final stage that takes the `base` stage and the `otf-agent` binary
FROM base AS otf-agent
COPY $TARGETPLATFORM/otf-agent /usr/local/bin/
USER 4096:4096
ENTRYPOINT ["/usr/local/bin/otf-agent"]

# STAGE: otf-job
# Final stage with the `otf-job` binary. Debian, not the alpine `base`: a job
# runs the providers, and a provider that is linked against glibc and its
# libraries does not load with gcompat. The Ceph client libraries are for
# providers that manage a Ceph cluster, such as gathering/ceph.
FROM debian:trixie-slim AS otf-job
RUN apt-get update && \
  apt-get install -y --no-install-recommends \
    ca-certificates git openssh-client librados2 librbd1 && \
  rm -rf /var/lib/apt/lists/* && \
  useradd --uid 4096 --user-group --create-home otf
ARG TARGETPLATFORM
COPY $TARGETPLATFORM/otf-job /usr/local/bin/
USER 4096:4096
ENTRYPOINT ["/usr/local/bin/otf-job"]
