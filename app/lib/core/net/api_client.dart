/// The one place the app talks to the backend.
///
/// Every method returns a [Result] (CLAUDE.md: no throwing across layers), and
/// every request carries the Supabase access token. The token is read fresh
/// per call rather than captured once, because Supabase refreshes it in the
/// background and a captured token starts 401ing an hour into a session.
library;

import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

import '../config.dart';
import 'result.dart';
import 'sse.dart';

/// Supplies the current access token, or null when signed out.
typedef TokenSource = String? Function();

class ApiClient {
  ApiClient({required TokenSource token, Dio? dio})
    : _token = token, // ignore: prefer_initializing_formals
      _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: AppConfig.apiBaseUrl,
              // A cold free-tier backend can take a while to answer the first
              // request (PRD §6), so the connect timeout is generous. The
              // receive timeout is not set at all for /chat: an answer streams
              // over tens of seconds and a receive timeout would cut it off
              // mid-sentence.
              connectTimeout: const Duration(seconds: 20),
              receiveTimeout: const Duration(seconds: 60),
              validateStatus: (_) => true,
            ),
          );

  final Dio _dio;
  final TokenSource _token;

  Map<String, String> _headers({String? contentType}) => {
    if (_token() case final t?) 'Authorization': 'Bearer $t',
    if (contentType != null) 'Content-Type': contentType,
  };

  /// Turn any response or transport error into a [Result].
  Result<T> _read<T>(Response<dynamic> response, T Function(dynamic) parse) {
    final status = response.statusCode ?? 0;
    if (status >= 200 && status < 300) {
      try {
        return Ok(parse(response.data));
      } catch (_) {
        return const Failure(FailureKind.server, message: 'unexpected response shape');
      }
    }
    return Failure(
      Failure.kindFor(status),
      message: _detail(response.data),
      statusCode: status,
    );
  }

  /// The backend writes `detail` for users (DESIGN §9), so it is worth showing.
  String? _detail(dynamic body) {
    if (body is Map && body['detail'] is String) return body['detail'] as String;
    if (body is Map && body['detail'] is List) {
      // FastAPI validation errors arrive as a list of objects.
      final first = (body['detail'] as List).firstOrNull;
      if (first is Map && first['msg'] is String) return first['msg'] as String;
    }
    return null;
  }

  Failure<T> _transportFailure<T>(Object error) {
    if (error is DioException) {
      final isNetwork =
          error.type == DioExceptionType.connectionError ||
          error.type == DioExceptionType.connectionTimeout ||
          error.error is SocketException;
      if (isNetwork) return const Failure(FailureKind.offline);
    }
    return Failure(FailureKind.server, message: error.toString());
  }

  // ── identity ──────────────────────────────────────────────────────────────

  /// Rename the caller (Settings). Blank clears the display name.
  Future<Result<Membership>> updateDisplayName(String displayName) async {
    try {
      final response = await _dio.patch<dynamic>(
        '/me',
        data: {'display_name': displayName},
        options: Options(headers: _headers(contentType: 'application/json')),
      );
      return _read(response, (data) => Membership.fromJson(data as Map<String, dynamic>));
    } catch (error) {
      return _transportFailure(error);
    }
  }

  Future<Result<Membership>> me() async {
    try {
      final response = await _dio.get<dynamic>(
        '/me',
        options: Options(headers: _headers()),
      );
      return _read(response, (data) => Membership.fromJson(data as Map<String, dynamic>));
    } catch (error) {
      return _transportFailure(error);
    }
  }

  Future<Result<Membership>> joinInstitution(
    String inviteCode, {
    String? displayName,
  }) async {
    try {
      final response = await _dio.post<dynamic>(
        '/institutions/join',
        data: {
          'invite_code': inviteCode,
          if (displayName != null) 'display_name': displayName,
        },
        options: Options(headers: _headers(contentType: 'application/json')),
      );
      return _read(response, (data) => Membership.fromJson(data as Map<String, dynamic>));
    } catch (error) {
      return _transportFailure(error);
    }
  }

  // ── chat ──────────────────────────────────────────────────────────────────

  /// The models the picker may offer, as the server lists them. Keys and
  /// names only; the model ids never leave the server.
  Future<Result<List<Map<String, dynamic>>>> models() async {
    try {
      final response = await _dio.get<dynamic>(
        '/models',
        options: Options(headers: _headers()),
      );
      return _read(
        response,
        (data) => [
          for (final m in (data as Map<String, dynamic>)['models'] as List)
            m as Map<String, dynamic>,
        ],
      );
    } catch (error) {
      return _transportFailure(error);
    }
  }

  /// Ask a question and receive the answer as it is written.
  ///
  /// Yields [SseEvent]s straight from the wire. The caller (the chat notifier)
  /// decides what each event means; this method's only job is to keep the
  /// connection open and hand over events without buffering.
  ///
  /// Errors arrive as an `error` event rather than an exception, so a stream
  /// that has already emitted half an answer never turns into a thrown object
  /// the UI has to unwind.
  Stream<SseEvent> chat({
    required String question,
    String? conversationId,
    String? attachmentId,
    String? model,
    List<Map<String, String>> history = const [],
  }) async* {
    try {
      final response = await _dio.post<ResponseBody>(
        '/chat',
        data: {
          'question': question,
          'history': history,
          if (conversationId != null) 'conversation_id': conversationId,
          if (attachmentId != null) 'attachment_id': attachmentId,
          if (model != null) 'model': model,
        },
        options: Options(
          headers: _headers(contentType: 'application/json'),
          responseType: ResponseType.stream,
          // The answer takes as long as it takes.
          receiveTimeout: Duration.zero,
        ),
      );

      final status = response.statusCode ?? 0;
      final body = response.data;
      if (body == null) {
        yield const SseEvent('error', {'detail': 'empty response'});
        return;
      }

      if (status < 200 || status >= 300) {
        // An error response is JSON, not a stream: drain it so the message
        // reaches the user instead of a bare status code.
        final raw = await utf8.decodeStream(body.stream.map((b) => b.toList()));
        yield SseEvent('error', {
          'detail': _detail(_tryJson(raw)) ?? 'request failed',
          'status': status,
        });
        return;
      }

      yield* decodeSse(body.stream.map((chunk) => chunk.toList()));
    } catch (error) {
      final failure = _transportFailure<void>(error);
      yield SseEvent('error', {
        'detail': failure.message,
        'offline': failure.kind == FailureKind.offline,
      });
    }
  }

  dynamic _tryJson(String raw) {
    try {
      return jsonDecode(raw);
    } on FormatException {
      return null;
    }
  }

  // ── attachments ───────────────────────────────────────────────────────────

  Future<Result<Map<String, dynamic>>> uploadAttachment({
    required String path,
    String? conversationId,
  }) async {
    try {
      final form = FormData.fromMap({
        'file': await MultipartFile.fromFile(path),
        if (conversationId != null) 'conversation_id': conversationId,
      });
      final response = await _dio.post<dynamic>(
        '/attachments',
        data: form,
        options: Options(headers: _headers(), receiveTimeout: const Duration(minutes: 3)),
      );
      return _read(response, (data) => data as Map<String, dynamic>);
    } catch (error) {
      return _transportFailure(error);
    }
  }

  /// The only call that confirms an extraction (CLAUDE.md #3). Until it
  /// returns, no join answer can be generated.
  Future<Result<Map<String, dynamic>>> confirmAttachment({
    required String attachmentId,
    required List<String> codes,
  }) async {
    try {
      final response = await _dio.patch<dynamic>(
        '/attachments/$attachmentId/confirm',
        data: {'codes': codes},
        options: Options(headers: _headers(contentType: 'application/json')),
      );
      return _read(response, (data) => data as Map<String, dynamic>);
    } catch (error) {
      return _transportFailure(error);
    }
  }

  // ── history and sources ───────────────────────────────────────────────────

  Future<Result<List<dynamic>>> conversations() async {
    try {
      final response = await _dio.get<dynamic>(
        '/conversations',
        options: Options(headers: _headers()),
      );
      return _read(
        response,
        (data) => (data as Map<String, dynamic>)['conversations'] as List,
      );
    } catch (error) {
      return _transportFailure(error);
    }
  }

  Future<Result<Map<String, dynamic>>> conversation(String id) async {
    try {
      final response = await _dio.get<dynamic>(
        '/conversations/$id',
        options: Options(headers: _headers()),
      );
      return _read(response, (data) => data as Map<String, dynamic>);
    } catch (error) {
      return _transportFailure(error);
    }
  }

  /// A signed, expiring URL for the document behind a citation (DESIGN §6.5).
  Future<Result<Map<String, dynamic>>> sourceFile(
    String documentId, {
    int page = 1,
  }) async {
    try {
      final response = await _dio.get<dynamic>(
        '/documents/$documentId/file',
        queryParameters: {'page': page},
        options: Options(headers: _headers()),
      );
      return _read(response, (data) => data as Map<String, dynamic>);
    } catch (error) {
      return _transportFailure(error);
    }
  }

  // ── documents (admin) ─────────────────────────────────────────────────────

  Future<Result<List<dynamic>>> documents() async {
    try {
      final response = await _dio.get<dynamic>(
        '/documents',
        options: Options(headers: _headers()),
      );
      return _read(
        response,
        (data) => (data as Map<String, dynamic>)['documents'] as List,
      );
    } catch (error) {
      return _transportFailure(error);
    }
  }

  Future<Result<Map<String, dynamic>>> publishDocument({
    required String path,
    required String title,
    required String audience,
  }) async {
    try {
      final form = FormData.fromMap({
        'file': await MultipartFile.fromFile(path),
        'title': title,
        'audience': audience,
      });
      final response = await _dio.post<dynamic>(
        '/documents',
        data: form,
        options: Options(headers: _headers(), receiveTimeout: const Duration(minutes: 3)),
      );
      return _read(response, (data) => data as Map<String, dynamic>);
    } catch (error) {
      return _transportFailure(error);
    }
  }
}

/// Who the caller is, as the backend resolved them from `profiles`.
class Membership {
  const Membership({
    required this.userId,
    required this.institutionId,
    required this.role,
    this.email,
    this.institutionName,
    this.displayName,
    this.inviteCode,
  });

  factory Membership.fromJson(Map<String, dynamic> json) => Membership(
    userId: json['user_id'] as String,
    institutionId: json['institution_id'] as String,
    role: json['role'] as String,
    email: json['email'] as String?,
    institutionName: json['institution_name'] as String?,
    displayName: json['display_name'] as String?,
    inviteCode: json['invite_code'] as String?,
  );

  final String userId;
  final String institutionId;
  final String role;
  final String? email;
  final String? institutionName;

  /// The name chosen at join, if any (Home greets with it).
  final String? displayName;

  /// The code the member joined with (Settings shows it).
  final String? inviteCode;

  bool get isAdmin => role == 'admin';
  bool get isTeacher => role == 'teacher';
}
