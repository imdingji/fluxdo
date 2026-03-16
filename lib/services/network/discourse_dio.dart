import 'package:dio/dio.dart';
import 'package:dio_smart_retry/dio_smart_retry.dart';
import 'package:flutter/foundation.dart';

import '../../constants.dart';
import 'adapters/platform_adapter.dart';
import 'cookie/app_cookie_manager.dart';
import 'cookie/cookie_jar_service.dart';
import 'cookie/cookie_sync_service.dart';
import 'interceptors/gateway_proxy_interceptor.dart';
import 'interceptors/cf_challenge_interceptor.dart';
import 'interceptors/request_scheduler_interceptor.dart';
import 'interceptors/session_guard_interceptor.dart';
import 'interceptors/cronet_fallback_interceptor.dart';
import 'interceptors/error_interceptor.dart';
import 'interceptors/network_log_interceptor.dart';
import 'interceptors/redirect_interceptor.dart';
import 'interceptors/request_header_interceptor.dart';

/// 统一封装的 Dio 工厂
class DiscourseDio {
  static Dio create({
    Duration connectTimeout = const Duration(seconds: 30),
    Duration receiveTimeout = const Duration(seconds: 30),
    Map<String, dynamic>? defaultHeaders,
    String? baseUrl,
    int? maxConcurrent = 6,
    int? maxPerWindow,
    Duration? windowDuration,
    bool enableRetry = true,
    bool enableCfChallenge = true,
  }) {
    final dio = Dio(BaseOptions(
      baseUrl: baseUrl ?? AppConstants.baseUrl,
      connectTimeout: connectTimeout,
      receiveTimeout: receiveTimeout,
      headers: defaultHeaders,
      // 禁用自动重定向，手动处理以确保重定向时使用正确的 cookie
      followRedirects: false,
      // 包含重定向状态码，让我们手动处理
      validateStatus: (status) => status != null && status >= 200 && status < 400,
    ));

    // 1. 配置平台适配器
    configurePlatformAdapter(dio);

    // 1.5 Gateway 反向代理拦截器（ECH 时改写 URL 到 localhost）
    dio.interceptors.add(GatewayProxyInterceptor());

    // 2. 会话代守卫（最先执行，确保过期请求不进入后续拦截器）
    dio.interceptors.add(SessionGuardInterceptor());

    // 3. 并发限制（null 表示不限制）
    if (maxConcurrent != null) {
      dio.interceptors.add(RequestSchedulerInterceptor(
        maxConcurrent: maxConcurrent,
        maxPerWindow: maxPerWindow ?? 10,
        windowDuration: windowDuration ?? const Duration(seconds: 3),
      ));
    }

    // 4. Cookie 管理
    final cookieJarService = CookieJarService();
    if (cookieJarService.isInitialized) {
      dio.interceptors.add(AppCookieManager(cookieJarService.cookieJar));
    }

    // 5. Cronet 降级拦截器（在重试拦截器之前）
    dio.interceptors.add(CronetFallbackInterceptor(dio));

    // 6. 重试拦截器 (dio_smart_retry)
    if (enableRetry) {
      dio.interceptors.add(RetryInterceptor(
        dio: dio,
        logPrint: (msg) => debugPrint('[Dio Retry] $msg'),
        retries: 0, // TODO: 调试完成后改回 3
        retryDelays: const [
          Duration(seconds: 1),
          Duration(seconds: 2),
          Duration(seconds: 4),
        ],
        retryableExtraStatuses: {429, 502, 503, 504},
      ));
    }

    // 7. 请求头拦截器
    dio.interceptors.add(RequestHeaderInterceptor(CookieSyncService()));

    // 8. 重定向拦截器
    dio.interceptors.add(RedirectInterceptor(dio));

    // 9. 错误拦截器
    dio.interceptors.add(ErrorInterceptor());

    // 10. CF 验证拦截器
    if (enableCfChallenge) {
      dio.interceptors.add(CfChallengeInterceptor(
        dio: dio,
        cookieJarService: cookieJarService,
      ));
    }

    // 11. 网络日志拦截器（最后一个，记录最终结果）
    dio.interceptors.add(NetworkLogInterceptor());

    return dio;
  }
}
