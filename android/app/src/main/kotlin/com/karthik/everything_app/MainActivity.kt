package com.karthik.everything_app

import io.flutter.embedding.android.FlutterFragmentActivity

// FlutterFragmentActivity, not FlutterActivity: local_auth's biometric prompt is a
// fragment and throws `no_fragment_activity` under a plain FlutterActivity, which
// surfaces as the vault showing a fingerprint button that never opens the OS sheet.
class MainActivity : FlutterFragmentActivity()
