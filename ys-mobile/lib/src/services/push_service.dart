import 'api_client.dart';

class PushService {
  PushService(this._apiClient);

  // Keep the API client injected so enabling Firebase push later does not
  // change AppState wiring.
  // ignore: unused_field
  final ApiClient _apiClient;

  Future<void> registerCurrentDevice() async {
    // Firebase is intentionally disabled until android/app/google-services.json
    // and backend Firebase credentials are configured.
  }
}
