FROM alpine:latest

# 1. 安装依赖：git, build-base 用于编译, ip6tables 用于NAT, iproute2 用于网络配置
RUN apk add --no-cache git build-base ip6tables iproute2

# 2. 下载并编译 microsocks
RUN git clone https://github.com/rofl0r/microsocks.git /tmp/microsocks && \
    cd /tmp/microsocks && \
    make && \
    mv microsocks /usr/local/bin/ && \
    rm -rf /tmp/microsocks

# 3. 复制并设置入口脚本
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# 暴露 SOCKS5 默认端口
EXPOSE 1080

# 运行入口脚本
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
