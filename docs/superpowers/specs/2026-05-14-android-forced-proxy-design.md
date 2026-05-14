# Android 应用内强制代理设计

## 背景

FluxDO 已经具备应用内网络代理基础能力：`ProxySettingsService` 保存上游代理配置，`NetworkSettingsService` 负责启动本地 Rust 代理，Dio/rhttp/WebView 等网络链路通过现有适配器接入。当前目标是在 Android 客户端新增一个严格模式：用户手动配置 HTTP CONNECT 或 SOCKS5 代理后，FluxDO 自身所有网络流量都必须经过该代理。

本设计不实现 Android 系统级 VPN，不代理其他 App，也不修改系统代理设置。

## 目标

- Android 用户可以手动输入 HTTP 或 SOCKS5 代理地址、端口、用户名和密码。
- 开启强制代理后，FluxDO 自身所有请求都必须走该代理。
- 代理不可用、本地网关未启动、WebView 无法接入代理时，请求必须失败，不允许直连。
- 强制代理模式下目标域名解析交给上游代理，暂停本地 DOH 解析参与，避免 DNS 泄漏。
- 复用现有本地 Rust 代理作为统一网关，减少分散配置导致的漏流量风险。

## 非目标

- 不实现 Android `VpnService`。
- 不代理系统或其他 App 的流量。
- 不支持 HTTPS 代理服务器本身使用 TLS 的 `https://host:port` 形式。
- Shadowsocks 保留现有普通代理能力，但不纳入本次强制代理验收范围。
- 不承诺代理不可用时自动直连。

## 用户配置

在现有 HTTP 代理设置卡片中扩展配置：

- 协议：HTTP、SOCKS5。
- 主机：必填。
- 端口：必填，范围 1-65535。
- 用户名：可选。
- 密码：可选。
- 强制所有 FluxDO 流量走此代理：新增开关。

开启强制代理前必须通过基础配置校验。代理可用性测试失败不应自动关闭强制代理，也不应触发直连，只更新诊断状态并提示用户。

## 架构

采用本地强制代理网关：

```text
FluxDO 内部请求
  -> 127.0.0.1:<localProxyPort>
  -> Rust 本地代理网关
  -> 用户配置的 HTTP CONNECT / SOCKS5 上游代理
  -> linux.do / CDN / AI 服务 / 更新服务
```

`ProxySettingsService` 扩展为强制代理配置来源，新增 `forcedEnabled` 和运行态错误状态。`NetworkSettingsService` 继续作为网络运行态协调者：当强制代理开启且配置有效时，启动 `DohProxyService`，但以 `enableDoh=false` 的纯上游转发方式运行。

Rust 本地代理启动成功后，Dart 层记录本地端口，并将 Dio、rhttp、WebView、图片、AI、下载等网络入口统一指向 `127.0.0.1:<localProxyPort>`。配置变更时重启本地代理，旧端口不再使用。

## DNS 和 DOH

强制代理模式采用“代理优先”策略：

- FluxDO 不为目标站点执行本地 DOH 解析。
- 不向本地网络发起额外 DNS 查询来解析 linux.do、CDN 或 AI 服务域名。
- HTTP CONNECT 和 SOCKS5 目标域名交给上游代理处理。
- DOH 设置页保留，但在强制代理开启时显示“强制代理模式下暂停本地 DOH 解析，以避免 DNS 泄漏”。

如果未来需要支持“强制代理 + DOH/ECH”，应作为单独高级选项设计，并明确泄漏和兼容性风险。

## 请求覆盖

强制代理开启后必须覆盖以下网络入口：

- `DiscourseDio` 创建的论坛 API、预加载、搜索、通知、上传等请求。
- MessageBus 长轮询。它可以继续不受并发调度限制，但必须走本地代理。
- rhttp 适配器。强制模式下不允许直连目标站，代理固定为本地网关。
- Android WebView 登录页、Cloudflare 验证页和 WebView HTTP Adapter。必须通过 `ProxyController.setProxyOverride` 指向本地端口。
- 图片和 CDN 请求。需要审计 `CachedNetworkImage`、cache manager、Flutter 默认图片加载路径，不能确认走统一网络层的路径必须改造或在强制模式下禁用。
- AI 请求。继续通过 `createExternalHttpAdapter` 注入应用网络配置，强制模式下走本地网关。
- 下载、更新检查、日志上传或其他外部请求。所有 `Dio()`、`http.Client()`、`HttpClient()` 直建点需要审计并接入统一工厂，无法接入时在强制模式下拒绝执行。

## Fail Closed 规则

强制代理模式下采用严格失败策略：

- 配置无效：所有网络请求失败，错误为“强制代理未配置”。
- 本地代理未启动或端口未知：所有网络请求失败，错误为“强制代理网关未就绪”。
- Rust 本地代理启动失败：进入强制代理失败状态，所有请求失败。
- Android WebView proxy override 失败：登录页、验证页和 WebView HTTP Adapter 不加载直连，显示“WebView 无法使用强制代理，已阻止直连”。
- 代理测试失败：仅更新测试结果并提示，不自动关闭强制代理，不直连。
- 发现无法证明走代理的请求路径：强制模式下禁用该功能，直到接入统一网络层。

这些错误应尽量使用统一异常类型或错误码，便于 UI 展示和测试断言。

## UI 设计

在网络设置的 HTTP 代理卡片中扩展：

- 增加“强制所有 FluxDO 流量走此代理”开关。
- 开启后显示本地网关状态：运行中、启动中、失败。
- 显示本地网关端口：`127.0.0.1:<port>`。
- 显示上游代理摘要：`HTTP host:port` 或 `SOCKS5 host:port`。
- 显示覆盖状态：Dio/rhttp/WebView 已接入；如果 WebView 接入失败，显示阻断提示。
- 保留“测试代理”和“复制诊断日志”入口。

DOH 卡片在强制代理开启时显示说明，避免用户误以为 DOH 仍参与当前请求路径。

## 实现拆分

1. 配置层：扩展 `ProxySettingsService`，增加 `forcedEnabled`、配置校验、强制模式错误状态和持久化键。
2. 网关启动层：扩展 `NetworkSettingsService.shouldRunLocalProxy` 和 `_applyProxyState()`，强制代理开启时启动本地 Rust 代理，`enableDoh=false`，上游使用用户配置。
3. WebView 层：让 `_applyWebViewProxy()` 返回并保存成功状态。Android 强制模式下设置失败即进入 fail closed。
4. Adapter 层：在 `platform_adapter.dart`、`rhttp_adapter.dart`、`WebViewHttpAdapter` 增加强制模式守卫。未就绪时直接抛统一异常。
5. 网络入口审计：扫描并替换或阻断绕过统一网络层的 `Dio()`、`http.Client()`、`HttpClient()` 和图片加载路径。
6. UI 层：扩展 `HttpProxyCard`，在 DOH 卡片增加强制代理说明。
7. i18n：补齐中文、英文、繁体文案。
8. 测试：覆盖配置校验、fail closed、adapter 选择、WebView 代理状态和关键请求入口。

## 测试计划

自动化测试：

- `ProxySettingsService` 配置校验和持久化。
- 强制代理开启但配置无效时，请求守卫返回统一失败。
- 本地代理端口缺失时，Dio/rhttp/WebView Adapter 不允许继续请求。
- rhttp 强制模式下代理地址固定为本地网关。
- `NetworkSettingsService` 在强制代理配置变化时重启本地代理。

人工验证：

- Android 上配置可用 HTTP 代理，首页、话题详情、登录 WebView、Cloudflare 验证页、图片、通知长轮询、AI 请求均可用。
- Android 上配置不可用代理，上述请求全部失败，不发生直连。
- WebView proxy override 人为失败时，登录页不加载并显示阻断提示。
- 强制代理开启时，DOH 设置显示暂停说明。
- 关闭强制代理后恢复现有网络行为。

## 验收标准

- 开启强制代理且上游可用：Android 上 FluxDO 主要功能均可通过代理工作。
- 开启强制代理但上游不可用：所有 FluxDO 网络请求失败，不直连。
- 登录 WebView 和 WebView HTTP Adapter 未接入代理时不会加载直连。
- 强制代理模式下目标域名不通过本地 DOH 解析。
- 关闭强制代理后现有普通代理、DOH、rhttp、WebView 设置行为不被破坏。
