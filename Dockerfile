# =================================================================
# Stage 1: Builder - Fetch the correct gost v3 binary from the correct repo
# =================================================================
FROM alpine:latest AS builder

# 使用一个经过验证的、较新的、稳定的 gost v3 版本
ARG GOST_VERSION=v3.2.1
# 声明我们将使用这些由 buildx 自动传入的变量
ARG TARGETARCH
ARG TARGETVARIANT

# 安装构建依赖
RUN apk add --no-cache curl

# 【最终的、决定性的修正】
# 增加了一个 case 语句来处理不同架构文件名的细微差异。
# 特别是，它能将 TARGETARCH=arm 和 TARGETVARIANT=v7 正确地组合成 armv7。
RUN cd /tmp && \
    ARCH_SUFFIX=$(case ${TARGETARCH} in \
        "arm") echo "arm${TARGETVARIANT}" ;; \
        *) echo "${TARGETARCH}" ;; \
    esac) && \
    curl -f -L -o gost.tar.gz "https://github.com/go-gost/gost/releases/download/${GOST_VERSION}/gost_${GOST_VERSION#v}_linux_${ARCH_SUFFIX}.tar.gz" && \
    tar -xzf gost.tar.gz gost && \
    mv gost /usr/local/bin/gost && \
    chmod +x /usr/local/bin/gost && \
    rm gost.tar.gz

# =================================================================
# Stage 2: Final Image
# =================================================================
FROM alpine:latest

# 添加一个重试循环来处理 QEMU 环境中可能的瞬时网络故障
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

# 从 builder 阶段复制 gost 二进制文件
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
