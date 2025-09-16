# =================================================================
# Stage 1: Builder - Fetch the correct gost v3 binary from the correct repo
# =================================================================
FROM alpine:latest AS builder

# 使用一个经过验证的、较新的、稳定的 gost v3 版本
ARG GOST_VERSION=v3.2.1
# TARGETARCH 由 Docker buildx 自动提供 (例如 amd64, arm64)
ARG TARGETARCH

# 安装构建依赖
RUN apk add --no-cache curl

# 使用最可靠的多步方法，并为 curl 添加 --fail 标志
RUN cd /tmp && \
    curl -f -L -o gost.tar.gz "https://github.com/go-gost/gost/releases/download/${GOST_VERSION}/gost_${GOST_VERSION#v}_linux_${TARGETARCH}.tar.gz" && \
    tar -xzf gost.tar.gz gost && \
    mv gost /usr/local/bin/gost && \
    chmod +x /usr/local/bin/gost && \
    rm gost.tar.gz

# =================================================================
# Stage 2: Final Image
# =================================================================
FROM alpine:latest

# 【最终的、决定性的修正】
# 1. 使用正确的软件源: 明确启用 'edge/testing' 仓库，因为 tayga 在这里。
# 2. 保留重试机制: 即使源正确，网络问题也可能发生，重试机制保证了构建的健壮性。
RUN ATTEMPTS=0; \
    MAX_ATTEMPTS=5; \
    until (echo "https://dl-cdn.alpinelinux.org/alpine/edge/testing" >> /etc/apk/repositories && apk update && apk add --no-cache iproute2 tayga unbound curl); do \
        ATTEMPTS=$((ATTEMPTS + 1)); \
        if [ $ATTEMPTS -eq $MAX_ATTEMPTS ]; then \
            echo "apk command failed after $MAX_ATTEMPTS attempts, exiting."; \
            exit 1; \
        fi; \
        echo "apk command failed, retrying in 5 seconds (attempt ${ATTEMPTS}/${MAX_ATTEMPTS})..."; \
        sleep 5; \
    done

# 从 builder 阶段复制 gost 二进制文件 (修正了 --from 的拼写错误)
COPY --from=builder /usr/local/bin/gost /usr/local/bin/gost

# 复制配置文件和入口脚本
COPY unbound.conf /etc/unbound/unbound.conf
COPY tayga.conf /etc/tayga.conf
COPY entrypoint.sh /entrypoint.sh

# 使得入口脚本可执行
RUN chmod +x /entrypoint.sh

# 暴露默认的 SOCKS5 端口
EXPOSE 1080

# 设置入口点以运行我们的配置脚本
ENTRYPOINT ["/entrypoint.sh"]
