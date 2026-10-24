/// A user-facing business error. Screens show [message] directly.
class AppError implements Exception {
  AppError(this.code, this.message);
  final String code;
  final String message;

  @override
  String toString() => message;
}

class ValidationError extends AppError {
  ValidationError(String message, {String code = 'validation'})
    : super(code, message);
}

class NotFoundError extends AppError {
  NotFoundError(String message) : super('not_found', message);
}

class ConflictError extends AppError {
  ConflictError(String message, {String code = 'conflict'})
    : super(code, message);
}
