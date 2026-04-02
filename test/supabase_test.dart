import 'package:flutter_test/flutter_test.dart';
import 'package:moqi_challenge/services/supabase_service.dart';

void main() {
  test('Supabase connection test', () async {
    await SupabaseService.initialize();
    expect(SupabaseService.isInitialized, true);
  });
}
