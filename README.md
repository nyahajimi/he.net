# he.net IPv6 Proxy Pool

[![Docker Build CI](https://github.com/nyahajimi/he.net/actions/workflows/docker-publish.yml/badge.svg)](https://github.com/nyahajimi/he.net/actions/workflows/docker-publish.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

此 Docker 镜像提供一个自洽的、健壮的 SOCKS5 代理服务器。其核心设计目标是通过 [he.net](https://tunnelbroker.net/) 的免费 IPv6 隧道作为唯一的互联网出口，同时利用内置的 NAT64/DNS64 服务无缝兼容对传统 IPv4 资源的访问。

其最终效果是创建一个拥有海量（理论上接近 2^64 个）IPv6 源地址的动态代理池，所有通过此代理发出的流量都将源自一个纯 IPv6 网络。

**WARNING:项目仅用于学习交流，严禁违反当地法律法规；由使用该项目导致的一切问题均由使用者本人承担责任！**

## 核心架构

本镜像的实现基于一个“IPv6优先，通过翻译兼容IPv4”的网络模型，由以下几个关键组件协同工作：

1.  **IPv6 隧道 (6in4)**: 容器启动时，会自动建立一个到 he.net 的 6in4 SIT 隧道。此隧道被配置为容器内所有流量的**唯一默认路由**。
2.  **DNS64 服务 (Unbound)**: 容器内运行一个本地 Unbound DNS 解析器。所有 DNS 请求都被强制导向此服务。当查询一个只有 A 记录 (IPv4) 的域名时，Unbound 会依据 [RFC 6147](https://tools.ietf.org/html/rfc6147) 规范，动态地合成一个特殊的 AAAA 记录 (IPv6)。
3.  **NAT64 网关 (Tayga)**: 容器内运行一个 Tayga NAT64 网关。它负责翻译所有发往 DNS64 合成地址的流量，将其从 IPv6 包转换为 IPv4 包，并通过 he.net 隧道发出。
4.  **SOCKS5 代理 (gost)**: 使用高性能的 `gost` 作为 SOCKS5 代理服务器。它只负责监听端口并将请求交给容器的底层网络栈，无需任何复杂的路由逻辑。
5.  **源地址随机化**: 容器内核启用了 IPv6 隐私扩展 (`use_tempaddr=2`)。这意味着对于每个出站连接，内核都会倾向于从 he.net 分配的 `/64` 地址块中选择一个临时的、随机的源地址，从而实现代理池的效果。

## 主要特性

-   **纯 IPv6 出口**: 所有流量均通过 he.net 的 IPv6 隧道 egress，有效隐藏服务器的原始 IPv4 地址。
-   **内置 IPv4 兼容性**: 无需任何客户端配置，即可通过集成的 NAT64/DNS64 服务透明地访问 IPv4 网站与服务。
-   **动态 IP 端点支持**: 内置自动化脚本，可持续监控主机的公网 IPv4 地址变化，并在地址变更时自动更新 he.net 的隧道端点并重建隧道，完美支持动态 IP 环境。
-   **多平台支持**: 镜像被自动构建为支持多种主流 CPU 架构，确保在绝大多数 VPS 和硬件设备上都能原生运行。
-   **高度可配置**: 所有关键参数均通过环境变量进行配置，易于集成和部署。

## 快速开始

首先，从 GitHub Container Registry 拉取镜像：
```sh
docker pull ghcr.io/nyahajimi/he.net:latest
```

### 场景一：静态 IP 服务器
适用于拥有固定公网 IPv4 地址的服务器。

```sh
docker run -d \
  --name ipv6-proxy-pool \
  --restart=always \
  --cap-add=NET_ADMIN \
  -p 1080:1080 \
  -e HE_REMOTE_V4="<HE.net隧道服务器的IPv4>" \
  -e HE_LOCAL_V4="<您自己服务器的公-网IPv4>" \
  -e HE_IPV6_ADDR="<HE.net分配的客户端IPv6>" \
  -e SOCKS5_USER="your_user" \
  -e SOCKS5_PASS="your_secure_password" \
  ghcr.io/nyahajimi/he.net:latest
```

### 场景二：动态 IP 服务器
适用于家庭宽带或 IP 地址可能变化的服务器。

```sh
docker run -d \
  --name ipv6-proxy-pool \
  --restart=always \
  --cap-add=NET_ADMIN \
  -p 1080:1080 \
  -e HE_REMOTE_V4="<HE.net隧道服务器的IPv4>" \
  -e HE_LOCAL_V4="auto" \
  -e HE_IPV6_ADDR="<HE.net分配的客户端IPv6>" \
  -e HE_UPDATE_URL="<HE.net后台的Update URL>" \
  -e SOCKS5_USER="your_user" \
  -e SOCKS5_PASS="your_secure_password" \
  ghcr.io/nyahajimi/he.net:latest
```
**注意**: ` --cap-add=NET_ADMIN` 是**必需的**，因为它授予容器创建和管理其内部网络接口（如 `he-ipv6` 隧道）的权限。

## 配置

通过以下环境变量对容器进行配置：

| 变量 | 描述 | 是否必需 | 默认值 |
| :--- | :--- | :--- | :--- |
| `HE_REMOTE_V4` | he.net 隧道详情页面中的 "Server IPv4 Address"。 | **是** | (无) |
| `HE_LOCAL_V4` | 您自己服务器的公网 IPv4 地址。对于动态 IP 环境，请设置为 `auto`，容器将自动检测。 | **是** | (无) |
| `HE_IPV6_ADDR` | he.net 隧道详情页面中的 "Client IPv6 Address"。**必须**包含 `/64` 前缀，例如 `2001:470:xx:xx::2/64`。 | **是** | (无) |
| `HE_UPDATE_URL`| (可选) 用于动态 IP 更新。在 he.net 隧道详情页的 "Advanced" 选项卡中可以找到。提供此 URL 将启用后台 IP 自动更新服务。| 否 | (无) |
| `SOCKS5_PORT` | SOCKS5 代理监听的端口。 | 否 | `1080` |
| `SOCKS5_USER` | (可选) SOCKS5 代理的用户名。如果设置，则必须同时设置 `SOCKS5_PASS`。 | 否 | (无) |
| `SOCKS5_PASS` | (可选) SOCKS5 代理的密码。 | 否 | (无) |
| `UPDATE_INTERVAL`| 动态 IP 更新的检查间隔（秒）。 | 否 | `300` |

## 支持的架构

本镜像通过 CI/CD 自动构建并推送到一个多平台清单 (Multi-Platform Manifest) 中。Docker 客户端会自动拉取与您主机匹配的架构。

| 平台 | 状态 | 备注 |
| :--- | :--- | :--- |
| `linux/amd64` | ✅ 支持 | 主流 Intel/AMD 服务器 |
| `linux/arm64` | ✅ 支持 | AWS Graviton, Oracle ARM, 较新的树莓派 (64位系统) 等 |
| `linux/arm/v7`| ✅ 支持 | 树莓派 2/3/4 (32位系统) 等 |

## 验证代理

您可以使用 `curl` 来验证代理是否正常工作。

**检查 IPv6 出口地址 (访问一个纯 IPv6 网站):**
```sh
curl --socks5-hostname localhost:1080 https://ifconfig.co
# 预期输出: 您的 he.net 隧道的某个 IPv6 地址
```

**检查对 IPv4 的兼容性 (通过 NAT64 访问):**
```sh
curl --socks5-hostname localhost:1080 https://ifconfig.me
# 预期输出: he.net 隧道服务器的某个共享 IPv4 地址
```

## 从源码构建

如果您希望自行构建镜像：
1. 克隆本仓库。
2. 确保您的系统已安装 Docker 并已配置好 `buildx`。
3. 在仓库根目录运行以下命令：
   ```sh
   docker buildx build --platform linux/amd64,linux/arm64,linux/arm/v7 -t your-custom-name:latest .
   ```

## 许可证

本项目基于 [MIT 许可证](https://opensource.org/licenses/MIT) 发布。
