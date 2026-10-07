import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_controller.dart';

const socialCallbackScheme = 'app.uptrack.mobile.auth';

/// iOS offers email sign-in only. App Store Guideline 4.8 requires an
/// equivalent privacy-focused login (such as Sign in with Apple) next to
/// Google/GitHub, and the app has none yet.
bool get isSocialLoginAvailable => defaultTargetPlatform != TargetPlatform.iOS;

final socialProvidersProvider = FutureProvider<Set<String>>(
  (ref) async => isSocialLoginAvailable
      ? ref.watch(uptrackApiProvider).getAuthProviders()
      : const <String>{},
);

class SocialLoginCancelled implements Exception {}

abstract interface class SocialBrowser {
  Future<Uri> authenticate(Uri url);
}

class SystemSocialBrowser implements SocialBrowser {
  static const _channel = MethodChannel('app.uptrack.mobile/auth/browser');

  @override
  Future<Uri> authenticate(Uri url) async {
    try {
      final result = await _channel.invokeMethod<String>(
        'authenticate',
        <String, String>{'url': url.toString()},
      );
      if (result == null) throw SocialLoginCancelled();
      return Uri.parse(result);
    } on PlatformException catch (error) {
      if (error.code == 'CANCELLED') throw SocialLoginCancelled();
      rethrow;
    }
  }
}

final socialBrowserProvider = Provider<SocialBrowser>(
  (ref) => SystemSocialBrowser(),
);

class SocialAuthorization {
  const SocialAuthorization({required this.code, required this.verifier});
  final String code;
  final String verifier;
}

/// State and verifier live in memory only. A killed app starts a fresh flow;
/// the callback contains no usable bearer credential and is bound to S256 PKCE.
class SocialLoginRequest {
  SocialLoginRequest({required this.state, required this.verifier});

  factory SocialLoginRequest.create() {
    final random = Random.secure();
    String secret() =>
        base64UrlEncode(List<int>.generate(32, (_) => random.nextInt(256)))
            .replaceAll('=', '');
    return SocialLoginRequest(state: secret(), verifier: secret());
  }

  final String state;
  final String verifier;
  String get challenge =>
      base64UrlEncode(sha256.convert(ascii.encode(verifier)).bytes)
          .replaceAll('=', '');

  SocialAuthorization parseCallback(Uri uri) {
    if (uri.scheme != socialCallbackScheme ||
        uri.host != 'callback' ||
        uri.path.isNotEmpty ||
        uri.hasPort ||
        uri.userInfo.isNotEmpty ||
        uri.fragment.isNotEmpty ||
        uri.queryParameters.keys.any(
          (key) => key != 'state' && key != 'code',
        ) ||
        uri.queryParametersAll['state']?.length != 1 ||
        uri.queryParameters['state'] != state ||
        uri.queryParameters.containsKey('error') ||
        uri.queryParametersAll['code']?.length != 1) {
      throw const FormatException('Invalid social sign-in callback');
    }
    final code = uri.queryParameters['code']!;
    if (code.isEmpty || code.length > 128) {
      throw const FormatException('Invalid social sign-in code');
    }
    return SocialAuthorization(code: code, verifier: verifier);
  }
}
