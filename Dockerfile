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

# Download and extract gost v3 (using the correct URL and file format)
RUN curl -L "https://github.com/go-gost/gost/releases/download/${GOST_VERSION}/gost_${GOST_VERSION}_linux_${TARGETARCH}.tar.gz" | tar -xz -C /tmp gost && \
    mv /tmp/gost /usr/local/bin/gost && \
    chmod +x /usr/local/bin/gost

# =================================================================
# Stage 2: Final Image
# =================================================================
FROM alpine:latest

# Install runtime dependencies
RUN apk add --no-cache iproute2 tayga unbound curl

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
