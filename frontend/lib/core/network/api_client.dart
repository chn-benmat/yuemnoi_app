import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../config/app_config.dart';

enum ApiClientErrorType { timeout, connection, invalidResponse }

class ApiClientException implements Exception {
  const ApiClientException(this.type);

  final ApiClientErrorType type;
}

class ApiResponse {
  const ApiResponse({required this.statusCode, required this.data});

  final int statusCode;
  final dynamic data;
}

class ApiUpload {
  const ApiUpload({
    required this.fieldName,
    required this.bytes,
    required this.fileName,
  });

  final String fieldName;
  final List<int> bytes;
  final String fileName;
}

abstract interface class ApiClient {
  Future<ApiResponse> get(
    String path, {
    Map<String, dynamic>? queryParameters,
    Map<String, String>? headers,
  });

  Future<ApiResponse> post(
    String path, {
    Map<String, dynamic>? data,
    Map<String, String>? headers,
  });

  Future<Stream<String>> postStream(
    String path, {
    Map<String, dynamic>? data,
    Map<String, String>? headers,
  });

  Future<ApiResponse> postMultipart(
    String path, {
    required Map<String, String> fields,
    List<ApiUpload> files,
    Map<String, String>? headers,
  });

  Future<ApiResponse> put(
    String path, {
    Map<String, dynamic>? data,
    Map<String, String>? headers,
  });

  Future<ApiResponse> putMultipart(
    String path, {
    required Map<String, String> fields,
    List<ApiUpload> files,
    Map<String, String>? headers,
  });

  Future<ApiResponse> delete(String path, {Map<String, String>? headers});

  void close();
}

class DioApiClient implements ApiClient {
  DioApiClient({
    Dio? dio,
    String? baseUrl,
    String? appSecret,
    Duration requestTimeout = _defaultRequestTimeout,
  }) : _dio =
           dio ??
           Dio(
             BaseOptions(
               baseUrl: _resolveBaseUrl(baseUrl),
               connectTimeout: requestTimeout,
               sendTimeout: requestTimeout,
               receiveTimeout: requestTimeout,
               headers: const {'Accept': 'application/json'},
               validateStatus: (status) => status != null && status < 600,
             ),
           ) {
    final configuredSecret = (appSecret ?? AppConfig.appSecretKey).trim();
    if (configuredSecret.isNotEmpty) {
      _dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            options.headers['X-App-Secret'] = configuredSecret;
            handler.next(options);
          },
        ),
      );
    }
  }

  static const Duration _defaultRequestTimeout = Duration(seconds: 20);

  final Dio _dio;

  @override
  Future<ApiResponse> get(
    String path, {
    Map<String, dynamic>? queryParameters,
    Map<String, String>? headers,
  }) {
    return _send(
      path,
      method: 'GET',
      queryParameters: queryParameters,
      headers: headers,
    );
  }

  @override
  Future<ApiResponse> post(
    String path, {
    Map<String, dynamic>? data,
    Map<String, String>? headers,
  }) {
    return _send(path, method: 'POST', data: data, headers: headers);
  }

  @override
  Future<Stream<String>> postStream(
    String path, {
    Map<String, dynamic>? data,
    Map<String, String>? headers,
  }) async {
    try {
      final response = await _dio.post<ResponseBody>(
        path,
        data: data,
        options: Options(
          responseType: ResponseType.stream,
          headers: {
            ...?headers,
            'Accept': 'text/event-stream',
          },
        ),
      );

      final responseBody = response.data;
      if (responseBody == null) {
        throw const ApiClientException(ApiClientErrorType.invalidResponse);
      }

      return responseBody.stream
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter());
    } on DioException catch (error) {
      throw ApiClientException(_errorType(error));
    }
  }

  @override
  Future<ApiResponse> postMultipart(
    String path, {
    required Map<String, String> fields,
    List<ApiUpload> files = const [],
    Map<String, String>? headers,
  }) {
    final formData = _buildFormData(fields, files);
    return _send(path, method: 'POST', data: formData, headers: headers);
  }

  @override
  Future<ApiResponse> put(
    String path, {
    Map<String, dynamic>? data,
    Map<String, String>? headers,
  }) {
    return _send(path, method: 'PUT', data: data, headers: headers);
  }

  @override
  Future<ApiResponse> putMultipart(
    String path, {
    required Map<String, String> fields,
    List<ApiUpload> files = const [],
    Map<String, String>? headers,
  }) {
    final formData = _buildFormData(fields, files);
    return _send(path, method: 'PUT', data: formData, headers: headers);
  }

  @override
  Future<ApiResponse> delete(String path, {Map<String, String>? headers}) {
    return _send(path, method: 'DELETE', headers: headers);
  }

  FormData _buildFormData(Map<String, String> fields, List<ApiUpload> files) {
    final formData = FormData.fromMap(fields);
    for (final file in files) {
      formData.files.add(
        MapEntry(
          file.fieldName,
          MultipartFile.fromBytes(file.bytes, filename: file.fileName),
        ),
      );
    }
    return formData;
  }

  Future<ApiResponse> _send(
    String path, {
    String method = 'POST',
    Object? data,
    Map<String, dynamic>? queryParameters,
    Map<String, String>? headers,
    int maxRetries = 2,
  }) async {
    var attempt = 0;
    while (true) {
      attempt++;
      try {
        final response = await _dio.request<Object?>(
          path,
          data: data,
          queryParameters: queryParameters,
          options: Options(method: method, headers: headers),
        );

        return ApiResponse(
          statusCode: response.statusCode ?? 0,
          data: _decodeResponse(response.data),
        );
      } on DioException catch (error) {
        final isRetryable = _isRetryable(error);
        if (attempt <= maxRetries &&
            isRetryable &&
            (method == 'GET' || method == 'HEAD')) {
          await Future<void>.delayed(Duration(milliseconds: 500 * attempt));
          continue;
        }
        throw ApiClientException(_errorType(error));
      } on FormatException {
        throw const ApiClientException(ApiClientErrorType.invalidResponse);
      }
    }
  }

  bool _isRetryable(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.connectionError:
      case DioExceptionType.badCertificate:
      case DioExceptionType.unknown:
        return true;
      case DioExceptionType.badResponse:
        final status = error.response?.statusCode ?? 0;
        return status == 502 || status == 503 || status == 504 || status == 429;
      case DioExceptionType.cancel:
      case DioExceptionType.transformTimeout:
        return false;
    }
  }

  dynamic _decodeResponse(Object? responseData) {
    if (responseData == null || responseData == '') {
      return const <String, dynamic>{};
    }

    final decoded = responseData is String
        ? jsonDecode(responseData)
        : responseData;
    if (decoded is Map) {
      return Map<String, dynamic>.from(decoded);
    }
    return decoded;
  }

  ApiClientErrorType _errorType(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
        return ApiClientErrorType.timeout;
      case DioExceptionType.badResponse:
        return ApiClientErrorType.invalidResponse;
      case DioExceptionType.cancel:
      case DioExceptionType.connectionError:
      case DioExceptionType.badCertificate:
      case DioExceptionType.unknown:
        return ApiClientErrorType.connection;
    }
  }

  static String _resolveBaseUrl(String? baseUrl) {
    var configuredUrl = (baseUrl ?? AppConfig.apiUrl).trim();
    if ((configuredUrl.startsWith('"') && configuredUrl.endsWith('"')) ||
        (configuredUrl.startsWith("'") && configuredUrl.endsWith("'"))) {
      configuredUrl = configuredUrl
          .substring(1, configuredUrl.length - 1)
          .trim();
    }
    while (configuredUrl.endsWith('/')) {
      configuredUrl = configuredUrl.substring(0, configuredUrl.length - 1);
    }
    if (configuredUrl.isEmpty) {
      configuredUrl = 'http://127.0.0.1:8080';
    }

    final isDesktopOrWeb = kIsWeb ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.iOS;

    if (isDesktopOrWeb && configuredUrl.contains('10.0.2.2')) {
      configuredUrl = configuredUrl.replaceAll('10.0.2.2', '127.0.0.1');
    }

    return configuredUrl;
  }

  @override
  void close() {
    _dio.close(force: true);
  }
}
