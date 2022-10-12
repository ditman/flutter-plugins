// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/services.dart';
import 'package:google_identity_services_web/id.dart' as id;
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';
import 'package:jwt_decoder/jwt_decoder.dart' as jwt;

Map<String, dynamic>? _decodeResponse(id.CredentialResponse? response) {
  if (response != null) {
    return jwt.JwtDecoder.tryDecode(response.credential);
  }
  return null;
}

/// Converts a [id.CredentialResponse] to [GoogleSignInUserData].
GoogleSignInUserData gisCredentialToPluginUserData(
    id.CredentialResponse? response) {
  // `payload` fields described here:
  // https://developers.google.com/identity/gsi/web/reference/js-reference#credential
  final Map<String, dynamic>? payload = _decodeResponse(response);
  if (payload == null) {
    throw PlatformException(
      code: 'bad_jwt_payload',
      message: 'Exception raised from GoogleAuth.signIn()',
      details: 'Could not decode JWT payload of credential: $response',
    );
  }
  return GoogleSignInUserData(
    displayName: payload['name'],
    email: payload['email'],
    id: payload['sub'],
    photoUrl: payload['picture'],
    idToken: response!.credential,
  );
}

/// Checks the `exp` date of an optional CredentialResponse.
bool isGisCredentialFresh(id.CredentialResponse? response) {
  final Map<String, dynamic>? payload = _decodeResponse(response);
  if (payload != null) {
    // `exp` is given in seconds since epoch:
    // From the docs:
    //   "exp": 1596477600, // Unix timestamp of the assertion's expiration time
    return (payload['exp'] as int) >
        (DateTime.now().millisecondsSinceEpoch / 1000);
  }
  return false;
}

/// Extracts a `hint` for the Authorization process.
/// According to the docs, this is "The email address for the target user.",
/// but can also be the "sub" string.
///
/// See: https://developers.google.com/identity/oauth2/web/reference/js-reference#TokenClientConfig
/// See: https://developers.google.com/identity/protocols/oauth2/openid-connect#authenticationuriparameters
String? gisCredentialGetHint(id.CredentialResponse? response) {
  final Map<String, dynamic>? payload = _decodeResponse(response);
  if (payload != null) {
    return payload['sub'] ?? payload['email'];
  }
  return null;
}

/// Validates the incoming `scopes`.
void assertValidScopes(List<String> scopes) {
  assert(
      !scopes.any((String scope) => scope.contains(' ')),
      "OAuth 2.0 Scopes for Google APIs can't contain spaces. "
      'Check https://developers.google.com/identity/protocols/googlescopes '
      'for a list of valid OAuth 2.0 scopes.');
}
