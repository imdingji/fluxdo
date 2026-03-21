# Flatpak 打包方案

Linux 发布链路采用两阶段方案：

1. 在 Arch 固定构建环境里执行 `flutter build linux --release`，产出可运行的 Linux bundle。
2. 再用 `flatpak-builder` 只做封装，把上一步产物组装成 `.flatpak`。

这样做是为了绕开当前项目在 Linux 上的几类高风险点：

- `flutter_inappwebview_linux` 依赖 WPE WebKit，不同发行版包名和版本差异很大。
- `flutter_secure_storage_linux` 会被较新的 clang 以 `-Wdeprecated-literal-operator` 加 `-Werror` 卡住，需要在 CI 里补丁化处理。
- `rhttp`、`super_native_extensions` 的 Rust 构建链需要可控的 toolchain 和 PATH。

当前相关文件：

- `scripts/ci/build_linux_bundle.sh`
- `scripts/ci/patch_linux_plugins.sh`
- `scripts/ci/bundle_wpe_runtime_libs.sh`
- `scripts/ci/check_linux_bundle.sh`
- `scripts/ci/stage_flatpak_bundle.sh`
- `flatpak/com.github.lingyan000.fluxdo.yml`
- `.github/workflows/build.yaml`

已知边界：

- 目前优先保证 CI 能稳定产出 `.flatpak`，不是直接走 Flathub 提交流程。
- WPE 运行库已经尝试跟随 bundle 一起打包，但仍然要以后续真机验证为准，尤其是 WebView 播放、下载和站点兼容性。
- `flutter_secure_storage_linux` 的 clang 兼容补丁目前仍基于 pub cache 注入，不过已经脚本化，不需要手工改缓存目录。
