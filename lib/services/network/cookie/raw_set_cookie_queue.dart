import 'dart:convert';
import 'dart:io' as io;

import 'package:flutter/foundation.dart';

import '../../../constants.dart';
import 'cookie_jar_service.dart';
import 'cookie_logger.dart';
import 'strategy/platform_cookie_strategy.dart';

/// Dio 收到的原始 Set-Cookie 头持久化队列。
///
/// 打开 WebView 前调用 [flushToWebView] 将队列中的原始头写入 WebView cookie store。
/// 队列持久化到磁盘，杀进程重启后不丢失。
class RawSetCookieQueue {
  RawSetCookieQueue._internal();

  static final RawSetCookieQueue instance = RawSetCookieQueue._internal();

  String? _filePath;
  List<Map<String, String>>? _cache;

  /// 初始化队列存储路径（在 CookieJarService.initialize 中调用）
  Future<void> initialize(String appDocDir) async {
    _filePath = '$appDocDir/.cookies/pending_set_cookies.json';
    // 预加载缓存
    await _load();
  }

  bool get isInitialized => _filePath != null;

  /// Dio 收到 Set-Cookie 时入队并持久化
  Future<void> enqueue(String url, String rawHeader) async {
    if (_filePath == null) return;

    final queue = await _load();
    queue.add({'url': url, 'raw': rawHeader});
    await _save(queue);

    final name = _extractCookieName(rawHeader);
    CookieLogger.enqueue(name: name, url: url, queueSize: queue.length);
  }

  /// 打开 WebView 前调用，将队列中的原始 Set-Cookie 头写入 WebView。
  ///
  /// 返回成功写入的条数。
  Future<int> flushToWebView({Set<String>? excludeCookieNames}) async {
    final queue = await _load();
    if (queue.isEmpty) {
      // 队列空（冷启动或长时间无请求），从 jar 的 rawSetCookie 字段兜底
      return _flushFromJar(excludeCookieNames: excludeCookieNames);
    }

    final entries = queue
        .where((e) {
          final url = e['url'] ?? '';
          final raw = e['raw'] ?? '';
          if (url.isEmpty || raw.isEmpty) return false;
          if (excludeCookieNames == null || excludeCookieNames.isEmpty) {
            return true;
          }
          return !excludeCookieNames.contains(_extractCookieName(raw));
        })
        .map((e) => (e['url']!, e['raw']!))
        .toList();

    final strategy = PlatformCookieStrategy.create();
    final written = await strategy.writeRawCookiesToWebView(entries);

    // 保留写入失败的（写入数 < 队列数时有残留）
    if (written >= entries.length) {
      await _save([]);
    }

    CookieLogger.flush(queued: queue.length, written: written);
    return written;
  }

  /// 清空队列（退出登录时调用）
  Future<void> clear() async {
    _cache = [];
    await _save([]);
  }

  // ---------------------------------------------------------------------------
  // 私有方法
  // ---------------------------------------------------------------------------

  /// 从 jar 的 rawSetCookie 字段兜底写入 WebView
  Future<int> _flushFromJar({Set<String>? excludeCookieNames}) async {
    final jar = CookieJarService();
    if (!jar.isInitialized) await jar.initialize();

    final cookies = await jar.loadAllCanonicalCookies();
    final entries = cookies
        .where((c) {
          if (c.rawSetCookie == null || c.rawSetCookie!.isEmpty) return false;
          if (excludeCookieNames == null || excludeCookieNames.isEmpty) {
            return true;
          }
          return !excludeCookieNames.contains(c.name);
        })
        .map((c) => (c.originUrl ?? AppConstants.baseUrl, c.rawSetCookie!))
        .toList();

    if (entries.isEmpty) return 0;

    final strategy = PlatformCookieStrategy.create();
    final written = await strategy.writeRawCookiesToWebView(entries);

    if (written > 0) {
      CookieLogger.flush(queued: entries.length, written: written);
    }
    return written;
  }

  Future<List<Map<String, String>>> _load() async {
    if (_cache != null) return _cache!;
    final path = _filePath;
    if (path == null) {
      _cache = [];
      return _cache!;
    }

    final file = io.File(path);
    if (!await file.exists()) {
      _cache = [];
      return _cache!;
    }

    try {
      final content = await file.readAsString();
      if (content.trim().isEmpty) {
        _cache = [];
        return _cache!;
      }
      final json = jsonDecode(content);
      _cache = (json as List)
          .whereType<Map>()
          .map((e) => e.map((k, v) => MapEntry(k.toString(), v.toString())))
          .toList();
    } catch (e) {
      debugPrint('[RawSetCookieQueue] 加载失败，重置队列: $e');
      _cache = [];
    }
    return _cache!;
  }

  Future<void> _save(List<Map<String, String>> queue) async {
    _cache = queue;
    final path = _filePath;
    if (path == null) return;

    try {
      final file = io.File(path);
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode(queue));
    } catch (e) {
      debugPrint('[RawSetCookieQueue] 持久化失败: $e');
    }
  }

  /// 从原始 Set-Cookie 头提取 cookie 名（用于日志）
  static String _extractCookieName(String rawHeader) {
    final eqIdx = rawHeader.indexOf('=');
    if (eqIdx <= 0) return rawHeader;
    return rawHeader.substring(0, eqIdx).trim();
  }
}
