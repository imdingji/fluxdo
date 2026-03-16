import 'package:flutter/foundation.dart';

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// DOH Proxy FFI bindings
///
/// This provides direct FFI bindings to the Rust DOH proxy library
/// for Android and iOS platforms.
class DohProxyFfi {
  DohProxyFfi._();
  static final DohProxyFfi instance = DohProxyFfi._();

  DynamicLibrary? _lib;
  bool _initialized = false;

  // FFI function types
  late final int Function(Pointer<Utf8> configJson) _dohProxyStartWithConfigJson;
  late final void Function() _dohProxyStop;
  late final int Function() _dohProxyIsRunning;
  late final int Function() _dohProxyGetPort;
  late final void Function() _dohProxyInitLogging;
  late final Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>) _dohProxyLookupEchConfig;
  late final void Function(Pointer<Utf8>) _dohProxyFreeString;

  /// Initialize FFI bindings
  bool initialize() {
    if (_initialized) return true;

    try {
      _lib = _loadLibrary();
      if (_lib == null) return false;

      // Load function pointers
      _dohProxyStartWithConfigJson = _lib!
          .lookup<NativeFunction<Int32 Function(Pointer<Utf8>)>>(
              'doh_proxy_start_with_config_json')
          .asFunction();

      _dohProxyStop = _lib!
          .lookup<NativeFunction<Void Function()>>('doh_proxy_stop')
          .asFunction();

      _dohProxyIsRunning = _lib!
          .lookup<NativeFunction<Int32 Function()>>('doh_proxy_is_running')
          .asFunction();

      _dohProxyGetPort = _lib!
          .lookup<NativeFunction<Int32 Function()>>('doh_proxy_get_port')
          .asFunction();

      _dohProxyInitLogging = _lib!
          .lookup<NativeFunction<Void Function()>>('doh_proxy_init_logging')
          .asFunction();

      _dohProxyLookupEchConfig = _lib!
          .lookup<NativeFunction<Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>)>>(
              'doh_proxy_lookup_ech_config')
          .asFunction();

      _dohProxyFreeString = _lib!
          .lookup<NativeFunction<Void Function(Pointer<Utf8>)>>('doh_proxy_free_string')
          .asFunction();

      _initialized = true;
      return true;
    } catch (e) {
      lastInitError = '初始化 FFI 绑定失败: $e';
      debugPrint('[DOH FFI] $lastInitError');
      return false;
    }
  }

  DynamicLibrary? _loadLibrary() {
    try {
      if (Platform.isAndroid) {
        return DynamicLibrary.open('libdoh_proxy.so');
      } else if (Platform.isIOS) {
        // iOS uses static linking, so we use the process itself
        return DynamicLibrary.process();
      } else if (Platform.isWindows) {
        return DynamicLibrary.open('doh_proxy.dll');
      } else if (Platform.isMacOS) {
        return _loadMacOSLibrary();
      } else if (Platform.isLinux) {
        return DynamicLibrary.open('libdoh_proxy.so');
      }
    } catch (e) {
      lastInitError = '加载原生库失败: $e';
      debugPrint('[DOH FFI] $lastInitError');
    }
    return null;
  }

  DynamicLibrary? _loadMacOSLibrary() {
    const libName = 'libdoh_proxy.dylib';
    final execPath = Platform.resolvedExecutable;
    final execDir = File(execPath).parent.path;
    // Platform.resolvedExecutable 在 macOS 指向 fluxdo.app/Contents/MacOS/fluxdo
    // dylib 位于 fluxdo.app/Contents/Frameworks/libdoh_proxy.dylib
    final candidates = <String>[
      '$execDir/../Frameworks/$libName',
      // 开发时：从 app bundle 路径反推项目根目录
      // build/macos/Build/Products/Debug/fluxdo.app/Contents/MacOS/ → 项目根
      ...() {
        // 尝试在路径中找到 /build/macos/ 来定位项目根目录
        final buildIdx = execPath.indexOf('/build/macos/');
        if (buildIdx > 0) {
          final projectRoot = execPath.substring(0, buildIdx);
          return [
            '$projectRoot/core/doh_proxy/target/release/$libName',
            '$projectRoot/core/doh_proxy/target/debug/$libName',
          ];
        }
        return <String>[];
      }(),
    ];
    for (final path in candidates) {
      if (File(path).existsSync()) {
        debugPrint('[DOH FFI] 加载 macOS 库: $path');
        return DynamicLibrary.open(path);
      }
    }
    // 最后尝试系统搜索路径
    return DynamicLibrary.open(libName);
  }

  /// 最近一次初始化失败的原因
  String? lastInitError;

  /// Start the DOH proxy server
  /// Returns the port number on success, or -1 on failure
  ///
  /// [port] - Port to bind (0 for auto-select)
  /// [preferIpv6] - Whether to prefer IPv6 addresses
  /// [dohServer] - DOH server URL (null for default Cloudflare)
  int start({
    int port = 0,
    bool enableDoh = true,
    bool preferIpv6 = false,
    bool gatewayMode = false,
    String? dohServer,
    String? dohServerEch,
    String? serverIp,
    String? upstreamProtocol,
    String? upstreamHost,
    int? upstreamPort,
    String? upstreamUsername,
    String? upstreamPassword,
    String? upstreamCipher,
  }) {
    if (!_initialized && !initialize()) {
      return -1;
    }

    final configJson = jsonEncode({
      'bind_addr': '127.0.0.1',
      'bind_port': port,
      'enable_doh': enableDoh,
      'gateway_mode': gatewayMode,
      'doh_server': dohServer ?? 'cloudflare',
      'prefer_ipv6': preferIpv6,
      'timeout_secs': 30,
      if (dohServerEch != null && dohServerEch.isNotEmpty)
        'doh_server_ech': dohServerEch,
      if (serverIp != null && serverIp.isNotEmpty)
        'server_ip': serverIp,
      if (upstreamHost != null && upstreamHost.isNotEmpty && upstreamPort != null && upstreamPort > 0)
        'upstream_proxy': {
          'protocol': upstreamProtocol ?? 'http',
          'host': upstreamHost,
          'port': upstreamPort,
          if (upstreamCipher != null && upstreamCipher.isNotEmpty)
            'cipher': upstreamCipher,
          if (upstreamUsername != null && upstreamUsername.isNotEmpty)
            'username': upstreamUsername,
          if (upstreamPassword != null && upstreamPassword.isNotEmpty)
            'password': upstreamPassword,
        },
    });
    final configPtr = configJson.toNativeUtf8();
    try {
      return _dohProxyStartWithConfigJson(configPtr);
    } finally {
      calloc.free(configPtr);
    }
  }

  /// Lookup ECH config for a host via DOH DNS HTTPS record.
  /// Returns raw ECH config bytes, or null if not available.
  Uint8List? lookupEchConfig(String host, String dohServer) {
    if (!_initialized && !initialize()) return null;

    final hostPtr = host.toNativeUtf8();
    final dohPtr = dohServer.toNativeUtf8();
    try {
      final resultPtr = _dohProxyLookupEchConfig(hostPtr, dohPtr);
      if (resultPtr == nullptr) return null;

      final jsonStr = resultPtr.toDartString();
      _dohProxyFreeString(resultPtr);

      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      if (map['ok'] == true && map['data'] is String) {
        return base64Decode(map['data'] as String);
      }
      debugPrint('[DOH FFI] ECH lookup: ${map['error'] ?? 'unknown error'}');
      return null;
    } finally {
      calloc.free(hostPtr);
      calloc.free(dohPtr);
    }
  }

  /// Stop the DOH proxy server
  void stop() {
    if (!_initialized) return;
    _dohProxyStop();
  }

  /// Check if the DOH proxy is running
  bool isRunning() {
    if (!_initialized) return false;
    return _dohProxyIsRunning() != 0;
  }

  /// Get the DOH proxy port
  int getPort() {
    if (!_initialized) return 0;
    return _dohProxyGetPort();
  }

  /// Initialize logging
  void initLogging() {
    if (!_initialized && !initialize()) return;
    _dohProxyInitLogging();
  }

  /// Check if FFI is available on this platform
  static bool get isAvailable {
    return Platform.isAndroid || Platform.isIOS || Platform.isMacOS;
  }

  /// 桌面平台 FFI 失败时可以回退到进程模式
  static bool get canFallbackToProcess {
    return Platform.isMacOS || Platform.isWindows || Platform.isLinux;
  }
}

/// Backwards compatibility alias
@Deprecated('Use DohProxyFfi instead')
typedef EchProxyFfi = DohProxyFfi;
