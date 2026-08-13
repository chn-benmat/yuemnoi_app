import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

enum ApiClientErrorType { timeout, connection, invalidResponse }

class ApiClientException implements Exception {
  const ApiClientException(this.type);

  final ApiClientErrorType type;
}

class ApiResponse {
  const ApiResponse({required this.statusCode, required this.data});

  final int statusCode;
  final Map<String, dynamic> data;
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
  Future<ApiResponse> post(
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

  void close();
}

class DioApiClient implements ApiClient {
  DioApiClient({
    Dio? dio,
    String? baseUrl,
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
           );

  static const Duration _defaultRequestTimeout = Duration(seconds: 20);

  final Dio _dio;

  @override
  Future<ApiResponse> post(
    String path, {
    Map<String, dynamic>? data,
    Map<String, String>? headers,
  }) {
    return _send(path, data: data, headers: headers);
  }

  @override
  Future<ApiResponse> postMultipart(
    String path, {
    required Map<String, String> fields,
    List<ApiUpload> files = const [],
    Map<String, String>? headers,
  }) {
    final formData = FormData.fromMap(fields);
    for (final file in files) {
      formData.files.add(
        MapEntry(
          file.fieldName,
          MultipartFile.fromBytes(file.bytes, filename: file.fileName),
        ),
      );
    }

    return _send(path, data: formData, headers: headers);
  }

  Future<ApiResponse> _send(
    String path, {
    Object? data,
    Map<String, String>? headers,
  }) async {
    try {
      final response = await _dio.post<Object?>(
        path,
        data: data,
        options: headers == null ? null : Options(headers: headers),
      );

      return ApiResponse(
        statusCode: response.statusCode ?? 0,
        data: _decodeResponse(response.data),
      );
    } on DioException catch (error) {
      throw ApiClientException(_errorType(error));
    } on FormatException {
      throw const ApiClientException(ApiClientErrorType.invalidResponse);
    }
  }

  Map<String, dynamic> _decodeResponse(Object? responseData) {
    if (responseData == null || responseData == '') {
      return const {};
    }

    final decoded = responseData is String
        ? jsonDecode(responseData)
        : responseData;
    if (decoded is Map) {
      return decoded.map((key, value) => MapEntry(key.toString(), value));
    }

    throw const FormatException('Response body must be a JSON object');
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
    final configuredUrl = (baseUrl ?? dotenv.env['API_URL'] ?? '').trim();
    var normalizedUrl = configuredUrl;
    while (normalizedUrl.endsWith('/')) {
      normalizedUrl = normalizedUrl.substring(0, normalizedUrl.length - 1);
    }
    if (normalizedUrl.isEmpty) {
      throw StateError('API_URL is not configured in .env.local.');
    }

    return normalizedUrl;
  }

  @override
  void close() {
    _dio.close(force: true);
  }
}
