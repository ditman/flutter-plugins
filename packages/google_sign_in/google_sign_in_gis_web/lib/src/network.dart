// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';
import 'package:http/http.dart' as http;

/// The scopes required to get userinfo on Oauth2 flows.
///
/// The oauth2 flows no longer return the User Profile, so we synthesize that
/// information by requesting it directly from the People API.
///
/// However, that might need a couple extra scopes that might not be set by
/// the user.
final List<String> peopleApiScopes = <String>[
  // 'https://www.googleapis.com/auth/userinfo.email',
  // 'https://www.googleapis.com/auth/userinfo.profile',
];

final Uri _peopleApiRequestUri = Uri(
  scheme: 'https',
  host: 'content-people.googleapis.com',
  path: 'v1/people/me',
  queryParameters: <String, Object?>{
    'sources': 'READ_SOURCE_TYPE_PROFILE',
    'personFields': 'metadata,photos,names,emailAddresses',
  }
);

/// Queries the People API v1 to synthesize a GoogleSignInUserData object.
Future<GoogleSignInUserData?> getUserDataFromPeopleApi(String accessToken) async {
  final http.Response response = await http.get(
    _peopleApiRequestUri,
    headers: <String, String>{
      'Authorization': 'Bearer $accessToken',
    });

  print(response);

  return null;
}
