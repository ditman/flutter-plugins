# google\_sign\_in\_gis\_web

A web implementation of [google_sign_in](https://pub.dev/packages/google_sign_in)
using the new Google Identity Services SDK.

It uses [package:google_identity_services_web](https://pub.dev/packages/google_identity_services_web)
as its JS-interop layer.

## Migrating from `package:google_sign_in_web`

Even though this package attempts to be API-compatible with the old one,
there are some fundamental behavior changes in the underlying
SDKs that warranted making this a **completely separate package.**

### What has changed?

**In a nutshell:**

* **Authentication:** [Migrating from Google Sign-In](https://developers.google.com/identity/gsi/web/guides/migration)
* **Authorization (Oauth2):** [Migrate to Google Identity Services](https://developers.google.com/identity/oauth2/web/guides/migration-to-gis)

### Separation of Authentication and Authorization

The previous SDK allowed to pass `scopes` as part of the Authentication process,
and the Authentication and Authorization tokens would be returned at the same
time.

Google Sign In SDK doesn't allow this but the plugin will attempt to mimic the old
behavior of authenticating + authorizing the user.
**This might result in the user being presented with multiple cards/popups.**

Users might decide to authenticate and authorize your app separately, so it's
not guaranteed that the [GoogleSignInTokenData](https://pub.dev/documentation/google_sign_in_platform_interface/latest/google_sign_in_platform_interface/GoogleSignInTokenData-class.html)
will contain either one of `idToken` (authentication) or `accessToken` (authorization)

Read more here:

* **Google Identity Services > [Separated Authentication and Authorization Moments](https://developers.google.com/identity/gsi/web/guides/overview#separated_authentication_and_authorization_moments)**

### Google Identity Services won't maintain your app state

Google Identity Services SDK will not attempt to auto-renew authentication or
authorization tokens; **it is now the responsibility of your site to handle
per user session state.**

Read more here:

* **Google Identity Services > [User sign-in to your site](https://developers.google.com/identity/gsi/web/guides/overview#user_sign-in_to_your_site)**
* **Migrating from Google Sign-In > [Session state and Listeners](https://developers.google.com/identity/gsi/web/guides/migration#session_state_and_listeners)**

#### Firebase Authentication

Take a look at [Firebase Authentication](https://firebase.google.com/docs/auth)
as a ready-made layer on top of Google (and other federated identity providers)
to more easily accomodate this change.

## Usage

### Import the package

This package is not an endorsed implementation of the google_sign_in plugin
yet, so you'll need to [add it explicitly.](https://pub.dev/packages/google_sign_in_gis_web/install)

### Web integration

First, go through the instructions [here](https://developers.google.com/identity/gsi/web/guides/get-google-api-clientid)
to create your Google Sign-In OAuth client ID.

On your `web/index.html` file, add the following `meta` tag, somewhere in the
`head` of the document:

```html
<meta name="google-signin-client_id" content="YOUR_GOOGLE_SIGN_IN_OAUTH_CLIENT_ID.apps.googleusercontent.com">
```

For this plugin to work correctly, the last step is to configure the
**Authorized JavaScript origins**, which _identify the domains from which your
application can send API requests._ When in local development, this is normally
`localhost` and some port.

You can do this by:

1. Going to the [Credentials page.](https://console.developers.google.com/apis/credentials)
2. Clicking "Edit" in the OAuth 2.0 Web application client that you created above.
3. Adding the URIs you want to the **Authorized JavaScript origins**.

For local development, may add a `localhost` entry, for example: `http://localhost:7357`

#### Starting flutter in http://localhost:7357

Normally `flutter run` starts in a random port. In the case where you need to
deal with authentication like the above, that's not the most appropriate
behavior.

You can tell `flutter run` to listen for requests in a specific hostname and
port with the following command:

```sh
flutter run -d chrome --web-hostname localhost --web-port 7357
```

or, to test with different browsers:

```sh
flutter run -d web-server --web-hostname localhost --web-port 7357
```

### Using Google APIs

See:

* **Using the token model > [Working with Tokens](https://developers.google.com/identity/oauth2/web/guides/use-token-model#working_with_tokens)**

[`package:googleapis`](https://pub.dev/packages/googleapis) provides
auto-generated REST clients to **many** Google APIs, like the
[people.v1 API.](https://pub.dev/documentation/googleapis/latest/people.v1/people.v1-library.html)

## Example

Find the example wiring in the [Google sign-in example application.](https://github.com/flutter/plugins/blob/main/packages/google_sign_in/google_sign_in/example/lib/main.dart)

## More API details

The Google Identity Services JavaScript SDK documentation can be found here:

* [Google Identity Services JavaScript SDK](https://developers.google.com/identity/oauth2/web)

The JS-interop layer implementing the above SDK can be found here:

* [package:google_identity_services_web](https://pub.dev/packages/google_identity_services_web)

## Contributions and Testing

Tests are crucial for contributions to this package. All new contributions
should be reasonably tested.

**Check the [`test/README.md` file](https://github.com/flutter/plugins/blob/main/packages/google_sign_in/google_sign_in_gis_web/test/README.md)**
for more information on how to run tests on this package.

Contributions to this package are welcome. Read the
[Contributing to Flutter Plugins](https://github.com/flutter/plugins/blob/main/CONTRIBUTING.md)
guide to get started.

### Issues and feedback

Please file [issues](https://github.com/flutter/flutter/issues/new)
to send feedback or report bugs.

**Thank you!**
