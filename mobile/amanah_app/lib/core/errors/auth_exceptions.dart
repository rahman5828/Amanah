// Typed authentication and session errors for AMANAH.
// Prefer these over string matching on Exception messages.

class AuthException implements Exception {
  final String message;
  const AuthException(this.message);

  @override
  String toString() => message;
}

/// No access token is stored (cold start without a session).
class NotAuthenticatedException extends AuthException {
  const NotAuthenticatedException([
    super.message = 'Not authenticated',
  ]);
}

/// HTTP 401 — invalid or expired session. Token should be cleared.
class SessionExpiredException extends AuthException {
  const SessionExpiredException([
    super.message = 'Session expired',
  ]);
}

/// HTTP 403 — authenticated but not allowed. Do not clear token automatically.
class ForbiddenException extends AuthException {
  const ForbiddenException([
    super.message = 'Access denied',
  ]);
}

/// Network failure, timeout, or connection error. Preserve token.
class NetworkException extends AuthException {
  const NetworkException([
    super.message = 'Unable to reach the server',
  ]);
}

/// HTTP 5xx or unexpected server response. Preserve token.
class ServerException extends AuthException {
  const ServerException([
    super.message = 'Server error',
  ]);
}

/// Malformed JSON or unexpected response body. Preserve token unless 401.
class ResponseParseException extends AuthException {
  const ResponseParseException([
    super.message = 'Invalid server response',
  ]);
}
