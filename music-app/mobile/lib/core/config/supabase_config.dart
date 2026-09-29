class SupabaseConfig {
  static const url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://gbqmtmcjqdqgfkzuwqot.supabase.co',
  );

  // Supabase publishable keys are designed to ship in client apps. Database
  // security is enforced by RLS; service-role keys must never be added here.
  static const publishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: 'sb_publishable__Vqh6AU8KimNPSNGeX_tFA_4ieBRkqS',
  );

  static const mobileCallback = 'com.innerwave.mobile://login-callback/';
}
