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

import 'src/network.dart';
import 'src/utils.dart';

const String _kClientIdMetaSelector = 'meta[name=google-signin-client_id]';
const String _kClientIdAttributeName = 'content';

/// Implementation of the google_sign_in plugin for Web.
class GoogleSignInGisWeb extends GoogleSignInPlatform {
  /// Constructs the plugin immediately and begins initializing it in the
  /// background.
  ///
  /// The plugin is completely initialized when [initialized] completed.
  GoogleSignInGisWeb() {
    _autoDetectedClientId = html
        .querySelector(_kClientIdMetaSelector)
        ?.getAttribute(_kClientIdAttributeName);

    _isGisLoaded = loader.loadWebSdk();
  }

  late Future<void> _isGisLoaded;

  bool _isInitCalled = false;

  late List<String> _requestedScopes;

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
    GoogleSignInPlatform.instance = GoogleSignInGisWeb();
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

    // We store the scopes so we can add "userinfo.email" and "userinfo.profile"
    // later, if needed to synthesize a [GoogleSignInUserData] object from a
    // request to the people API.
    _requestedScopes = params.scopes;

    await _isGisLoaded;

    // Init the identity provider...
    id.initialize(id.IdConfiguration(
      client_id: appClientId!,
      callback: allowInterop(_credentialResponse.add),
      auto_select: true,
    ));

    // Init the Token client...
    _tokenClient = oauth.initTokenClient(oauth.TokenClientConfig(
      hosted_domain: params.hostedDomain,
      scope: <String>[
        ..._requestedScopes,
        ...peopleApiScopes,
      ].join(','),
      client_id: appClientId,
      callback: allowInterop(_tokenResponse.add),
    ));

    // Remember the last responses the stream has seen...
    _credentialResponse.stream.listen((id.CredentialResponse response) {
      _lastCredentialResponse = response;
    }).onError((Object? error) {
      print(error);
      _lastCredentialResponse = null;
    }); // Never fail?

    _tokenResponse.stream.listen((oauth.TokenResponse response) {
      _lastTokenResponse = response;
    }).onError((Object? error) {
      print(error);
      _lastTokenResponse = null;
    }); // Never fail?

    // The library initialization is now complete.
    _isInitCalled = true;
  }

  /// Calls [id.prompt] to attempt to re-authenticate a returning user.
  @override
  Future<GoogleSignInUserData?> signInSilently() async {
    await initialized;
    // Attempt to prompt, we'll return the next entry on the
    // onUserData stream, coming from our identity callback.
    // This might throw a PlatformException.
    id.prompt(allowInterop(_onPromptNotification));
    try {
      // Await for the next credentialResponse (the "first" of a new subscription)
      // then convert it to a GoogleSignInUserData when ready...
      return _credentialResponse.stream.first.then(gisCredentialToPluginUserData);
    } on PlatformException catch (e) {
      // The card didn't work for some reason, see [_onPromptNotification].
      print(e);
    }
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

  /// Attempt to sign-in and authorize using the oauth2 implicit flow.
  ///
  /// This uses the TokenClient, that might trigger a pop-up authentication flow,
  /// however the plugin will not give us the GoogleSignInUserData.
  ///
  /// If at that point, we still don't have any user data, we'll synthesize it by
  /// making a request to the "profile.readonly" API and attempting to read it
  /// from there.
  @override
  Future<GoogleSignInUserData?> signIn() async {
    await initialized;

    _tokenClient.requestAccessToken(oauth.OverridableTokenClientConfig(
      hint: gisCredentialGetHint(_lastCredentialResponse),
    ));

    if (_lastCredentialResponse == null) {
      return _tokenResponse.stream.first.then(
        (oauth.TokenResponse token) => getUserDataFromPeopleApi(token.access_token)
      );
    } else {
      return gisCredentialToPluginUserData(_lastCredentialResponse);
    }
    // The access_token will be available through `getTokens`.
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
