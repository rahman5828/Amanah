class ApiConfig {
  static const String baseUrl = 'http://10.0.2.2:8000';

  static const String registerEndpoint = '/api/v1/auth/register';
  static const String loginEndpoint = '/api/v1/auth/login';
  static const String refreshEndpoint = '/api/v1/auth/refresh';
  static const String logoutEndpoint = '/api/v1/auth/logout';
  static const String sessionsEndpoint = '/api/v1/auth/sessions';
  static const String profileEndpoint = '/api/v1/users/me';
}
