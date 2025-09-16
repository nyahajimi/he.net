# =================================================================
# Stage 1: Builder - Fetch the correct gost v3 binary from the correct repo
# =================================================================
FROM alpine:latest AS builder

# Use a recent version of gost v3
ARG GOST_VERSION=v3.0.0-rc10
# TARGETARCH is automatically provided by Docker buildx (e.g., amd64, arm64)
ARG TARGETARCH

# Install build dependencies
RUN apk add --no-cache curl

# Download the archive and pipe it to tar.
# Tell tar to extract *only* the 'gost' file and output it to stdout (-O).
# Redirect that output directly into the final destination file.
RUN curl -L "https://github.com/go-gost/gost/releases/download/${GOST_VERSION}/gost_${GOST_VERSION}_linux_${TARGETARCH}.tar.gz" | \
    tar -xz -O gost > /usr/local/bin/gost && \
    chmod +x /usr/local/bin/gost

# =================================================================
# Stage 2: Final Image
# =================================================================
FROM alpine:latest

# 【关键修改点】
# Enable community repository, UPDATE the package index, then install packages.
# This entire sequence is done in a single RUN to keep the image layer small.
RUN echo "https://dl-cdn.alpinelinux.org/alpine/latest-stable/community" >> /etc/apk/repositories && \
    apk update && \
    apk upgrade -y --no-cache && \
    apk add --no-cache \
      iproute2 \
      tayga \
      unbound \
      curl

# Copy the gost binary from the builder stage
COPY --from=builder /usr/local/bin/gost /usr/local/bin/gost

# Copy configuration files and the entrypoint script
COPY unbound.conf /etc/unbound/unbound.conf
COPY tayga.conf /etc/tayga.conf
COPY entrypoint.sh /entrypoint.sh

# Make the entrypoint script executable
RUN chmod +x /entrypoint.sh

# Expose the default SOCKS5 port
EXPOSE 1080

# Set the entrypoint to run our configuration script
ENTRYPOINT ["/entrypoint.sh"]
