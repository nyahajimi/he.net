# --- STAGE 1: The Builder ---
FROM alpine:3.20 AS builder
RUN apk add --no-cache git build-base
RUN git clone https://github.com/rofl0r/microsocks.git /tmp/microsocks
RUN cd /tmp/microsocks && make

# --- STAGE 2: The Final Image ---
FROM alpine:3.20
RUN apk add --no-cache ip6tables iproute2
COPY --from=builder /tmp/microsocks/microsocks /usr/local/bin/
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh
EXPOSE 1080
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
