// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:html' as html; // TODO(dit): remove this dependency

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';

import 'package:google_identity_services_web/id.dart' as id;
import 'package:google_identity_services_web/loader.dart' as loader;
import 'package:google_identity_services_web/oauth2.dart' as oauth;

import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';
import 'package:js/js.dart' show allowInterop;

import 'src/utils.dart';

const String _kClientIdMetaSelector = 'meta[name=google-signin-client_id]';
const String _kClientIdAttributeName = 'content';

/// Implementation of the google_sign_in plugin for Web.
class GoogleSignInPlugin extends GoogleSignInPlatform {
  /// Constructs the plugin immediately and begins initializing it in the
  /// background.
  ///
  /// The plugin is completely initialized when [initialized] completed.
  GoogleSignInPlugin() {
    _autoDetectedClientId = html
        .querySelector(_kClientIdMetaSelector)
        ?.getAttribute(_kClientIdAttributeName);

    _isGisLoaded = loader.loadWebSdk();
  }

  late Future<void> _isGisLoaded;

  bool _isInitCalled = false;

  // A client used to authorize/revoke scopes.
  late oauth.TokenClient _tokenClient;

  // A Stream of [CredentialResponse] from GIS.
  final StreamController<id.CredentialResponse> _credentialResponse =
      StreamController<id.CredentialResponse>.broadcast();
  // A Stream of [TokenResponses] from GIS.
  final StreamController<oauth.TokenResponse> _tokenResponse =
      StreamController<oauth.TokenResponse>.broadcast();

  // The last CredentialResponse seen.
  id.CredentialResponse? _lastCredentialResponse;
  // The last TokenResponse seen.
  oauth.TokenResponse? _lastTokenResponse;

  // This method throws if init or initWithParams hasn't been called at some
  // point in the past. It is used by the [initialized] getter to ensure that
  // users can't await on a Future that will never resolve.
  void _assertIsInitCalled() {
    if (!_isInitCalled) {
      throw StateError(
        'GoogleSignInPlugin::init() or GoogleSignInPlugin::initWithParams() '
        'must be called before any other method in this plugin.',
      );
    }
  }

  /// A future that resolves when both GAPI and Auth2 have been correctly initialized.
  @visibleForTesting
  Future<void> get initialized {
    _assertIsInitCalled();
    return _isGisLoaded;
  }

  String? _autoDetectedClientId;

  /// Factory method that initializes the plugin with [GoogleSignInPlatform].
  static void registerWith(Registrar registrar) {
    GoogleSignInPlatform.instance = GoogleSignInPlugin();
  }

  @override
  Future<void> init({
    List<String> scopes = const <String>[],
    SignInOption signInOption = SignInOption.standard,
    String? hostedDomain,
    String? clientId,
  }) {
    return initWithParams(SignInInitParameters(
      scopes: scopes,
      signInOption: signInOption,
      hostedDomain: hostedDomain,
      clientId: clientId,
    ));
  }

  @override
  Future<void> initWithParams(SignInInitParameters params) async {
    final String? appClientId = params.clientId ?? _autoDetectedClientId;
    assert(
        appClientId != null,
        'ClientID not set. Either set it on a '
        '<meta name="google-signin-client_id" content="CLIENT_ID" /> tag,'
        ' or pass clientId when initializing GoogleSignIn');

    assert(params.serverClientId == null,
        'serverClientId is not supported on Web.');

    assertValidScopes(params.scopes);

    await _isGisLoaded;

    // Init the identity provider...
    id.initialize(id.IdConfiguration(
      client_id: appClientId!,
      callback: _credentialResponse.add,
      auto_select: true,
    ));

    // Init the Token client...
    _tokenClient = oauth.initTokenClient(oauth.TokenClientConfig(
      hosted_domain: params.hostedDomain,
      scope: params.scopes.join(' '),
      client_id: appClientId,
      callback: _tokenResponse.add,
    ));

    // Remember the last responses the stream has seen...
    _credentialResponse.stream.listen((id.CredentialResponse response) {
      _lastCredentialResponse = response;
    }).onError((Object? error) {
      _lastCredentialResponse = null;
    }); // Never fail?

    _tokenResponse.stream.listen((oauth.TokenResponse response) {
      _lastTokenResponse = response;
    }).onError((Object? error) {
      _lastTokenResponse = null;
    }); // Never fail?

    // The library initialization is now complete.
    _isInitCalled = true;
  }

  // Maybe attempt to .prompt() here?
  @override
  Future<GoogleSignInUserData?> signInSilently() async {
    await initialized;

    return null;
  }

  // Handles a "prompt moment notification" coming from GIS. In
  // most cases (except a successful login) this will inject an
  // error object into the [credentialResponse.stream].
  void _onPromptNotification(id.PromptMomentNotification status) {
    String? code;
    if (status.isNotDisplayed()) {
      code = status.getNotDisplayedReason().toString();
    } else if (status.isSkippedMoment()) {
      code = status.getSkippedReason().toString();
    } else if (status.getDismissedReason() !=
        id.MomentDismissedReason.credential_returned) {
      code = status.getDismissedReason().toString();
    }
    if (code != null) {
      _credentialResponse.addError(PlatformException(
        code: code,
        message: 'Exception raised from GoogleAuth.signIn()',
        details:
            'https://developers.google.com/identity/sign-in/web/reference#error_codes_2',
      ));
    }
  }

  @override
  Future<GoogleSignInUserData?> signIn() async {
    await initialized;
    // Attempt to prompt, we'll return the next entry on the
    // onUserData stream, coming from our identity callback.
    // This might throw a PlatformException.
    id.prompt(allowInterop(_onPromptNotification));
    // Await for the next credentialResponse (the "first" of a new subscription)
    final id.CredentialResponse response =
        await _credentialResponse.stream.first;
    _tokenClient.requestAccessToken(oauth.OverridableTokenClientConfig(
      hint: gisCredentialGetHint(response),
    ));
    await _tokenResponse.stream.first;
    // The access_token will be available through `getTokens`.
    return gisCredentialToPluginUserData(response);
  }

  @override
  Future<GoogleSignInTokenData> getTokens(
      {required String email, bool? shouldRecoverAuth}) async {
    await initialized;

    return GoogleSignInTokenData(
      idToken: _lastCredentialResponse?.credential,
      accessToken: _lastTokenResponse?.access_token,
    );
  }

  // Disconnects from authentication...
  @override
  Future<void> signOut() async {
    await initialized;

    id.disableAutoSelect();
  }

  @override
  Future<void> disconnect() async {
    await initialized;

    if (_lastCredentialResponse != null) {
      id.revoke(gisCredentialGetHint(_lastCredentialResponse)!);
    }
    if (_lastTokenResponse != null) {
      oauth.revokeToken(_lastTokenResponse!.access_token);
    }
  }

  @override
  Future<bool> isSignedIn() async {
    await initialized;

    return isGisCredentialFresh(_lastCredentialResponse);
  }

  @override
  Future<void> clearAuthCache({required String token}) async {
    await initialized;

    _lastCredentialResponse = null;
    _lastTokenResponse = null;
  }

  @override
  Future<bool> requestScopes(List<String> scopes) async {
    await initialized;

    assertValidScopes(scopes);

    _tokenClient.requestAccessToken(oauth.OverridableTokenClientConfig(
      scope: scopes.join(' '),
    ));

    final oauth.TokenResponse response = await _tokenResponse.stream.first;

    return scopes
        .every((String scope) => oauth.hasGrantedAllScopes(response, scope));
  }
}
