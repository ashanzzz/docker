# syntax=docker/dockerfile:1

ARG NEXTCLOUD_VERSION=33.0.0
FROM nextcloud:${NEXTCLOUD_VERSION}-apache

# Install extra system dependencies (edit packages.txt to extend)
COPY packages.txt /tmp/packages.txt

RUN set -eux; \
  apt-get update; \
  # Filter comments/blank lines so packages.txt can be documented.
  grep -vE '^\s*(#|$)' /tmp/packages.txt | xargs -r apt-get install -y --no-install-recommends; \
  rm -rf /var/lib/apt/lists/* /tmp/packages.txt
