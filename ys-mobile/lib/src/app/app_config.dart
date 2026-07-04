class AppConfig {
  static const apiBaseUrl = String.fromEnvironment(
    'YS_API_URL',
    defaultValue: 'http://192.168.71.87:3666/api/v1',
  );
}
