/// A chat message, and the states one can be in while it is being written.
library;

import 'citation.dart';

enum MessageRole { user, assistant }

/// What happened to an assistant message. The UI renders three of these very
/// differently (DESIGN §6.3): a normal answer, a not-found, and a failure.
enum AnswerStatus {
  /// Still arriving.
  streaming,

  /// Finished, grounded in sources.
  answered,

  /// The score floor refused it. Visually distinct, and never dressed up as an
  /// answer (DESIGN §6.3).
  notFound,

  /// The request or the generation failed. Retryable.
  failed,
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.role,
    required this.text,
    this.citations = const [],
    this.status = AnswerStatus.answered,
    this.attachmentId,
    this.errorDetail,
    this.readCourses,
    this.notSent = false,
  });

  /// A locally created message, before the server has given it an id.
  factory ChatMessage.user(String text, {String? attachmentId}) => ChatMessage(
    id: 'local-${DateTime.now().microsecondsSinceEpoch}',
    role: MessageRole.user,
    text: text,
    attachmentId: attachmentId,
  );

  /// The answer being waited for. [readCourses] is how many courses the
  /// user confirmed from a routine photo, shown as a finished step above the
  /// active "Searching documents" one.
  factory ChatMessage.pending({int? readCourses}) => ChatMessage(
    id: 'pending-${DateTime.now().microsecondsSinceEpoch}',
    role: MessageRole.assistant,
    text: '',
    status: AnswerStatus.streaming,
    readCourses: readCourses,
  );

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
    id: json['id'] as String,
    role: json['role'] == 'user' ? MessageRole.user : MessageRole.assistant,
    text: json['content'] as String? ?? '',
    citations: Citation.listFrom(json['citations']),
  );

  final String id;
  final MessageRole role;
  final String text;
  final List<Citation> citations;
  final AnswerStatus status;
  final String? attachmentId;

  /// The server's own wording for a failure, when it had one.
  final String? errorDetail;

  /// Assistant: courses read from the attached routine, for the steps card.
  final int? readCourses;

  /// User: the question never reached the server because the phone is
  /// offline. The bubble says so and offers Retry (CHANGES.md).
  final bool notSent;

  bool get isUser => role == MessageRole.user;
  bool get isStreaming => status == AnswerStatus.streaming;
  bool get isNotFound => status == AnswerStatus.notFound;
  bool get hasFailed => status == AnswerStatus.failed;

  /// An assistant message that has not produced a token yet: the thread shows
  /// its steps card instead of text.
  bool get isWorking => isStreaming && text.isEmpty;

  ChatMessage copyWith({
    String? id,
    String? text,
    List<Citation>? citations,
    AnswerStatus? status,
    String? errorDetail,
    bool? notSent,
  }) => ChatMessage(
    id: id ?? this.id,
    role: role,
    text: text ?? this.text,
    citations: citations ?? this.citations,
    status: status ?? this.status,
    attachmentId: attachmentId,
    errorDetail: errorDetail ?? this.errorDetail,
    readCourses: readCourses,
    notSent: notSent ?? this.notSent,
  );
}
