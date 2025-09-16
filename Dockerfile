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

# 【最终修正方案】
# 使用最可靠的多步方法：先下载，再解压，再移动。
# 这避免了所有管道(pipe)可能带来的不确定性。
RUN cd /tmp && \
    curl -L -o gost.tar.gz "https://github.com/go-gost/gost/releases/download/${GOST_VERSION}/gost_${GOST_VERSION}_linux_${TARGETARCH}.tar.gz" && \
    tar -xzf gost.tar.gz gost && \
    mv gost /usr/local/bin/gost && \
    chmod +x /usr/local/bin/gost && \
    rm gost.tar.gz

# =================================================================
# Stage 2: Final Image
# =================================================================
FROM alpine:latest

# Enable community repository, UPDATE the package index, then install packages.
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
