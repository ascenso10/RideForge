import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

/// Service for handling Garmin Connect API integration.
///
/// Uses OAuth 1.0a (3-legged, OOB flow):
///   1. [startAuthentication] → fetches a request token and returns the
///      authorization URL to open in a browser.
///   2. User authorizes the app on Garmin's page and receives a PIN.
///   3. [completeAuthentication] → exchanges the PIN for access tokens.
///
/// Requires developer credentials from https://developer.garmin.com/
/// Set [_consumerKey] and [_consumerSecret] before use.
class GarminService {
  // ── Garmin OAuth 1.0a endpoints ──────────────────────────────────────────
  static const String _requestTokenUrl =
      'https://oauth.garmin.com/oauth/request_token';
  static const String _authorizeUrl = 'https://connect.garmin.com/oauthConfirm';
  static const String _accessTokenUrl =
      'https://oauth.garmin.com/oauth/access_token';

  // ── Garmin Health API ─────────────────────────────────────────────────────
  static const String _apiBaseUrl = 'https://apis.garmin.com/wellness-api/rest';

  // ── App credentials ───────────────────────────────────────────────────────
  // Register your app at https://developer.garmin.com/ to obtain these.
  static const String _consumerKey = 'YOUR_CONSUMER_KEY';
  static const String _consumerSecret = 'YOUR_CONSUMER_SECRET';

  // ── SharedPreferences keys ────────────────────────────────────────────────
  static const String _keyAccessToken = 'garmin_access_token';
  static const String _keyAccessTokenSecret = 'garmin_access_token_secret';
  static const String _keyUserId = 'garmin_user_id';
  static const String _keyUserName = 'garmin_user_name';
  // Temporary keys used during the OAuth handshake
  static const String _keyRequestToken = 'garmin_request_token';
  static const String _keyRequestTokenSecret = 'garmin_request_token_secret';

  // ── Public API ────────────────────────────────────────────────────────────

  /// Returns `true` when valid access tokens are stored.
  Future<bool> isConnected() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyAccessToken) != null &&
        prefs.getString(_keyAccessTokenSecret) != null;
  }

  /// Returns the stored user info (may be null if not connected).
  Future<Map<String, String?>> getUserInfo() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'userId': prefs.getString(_keyUserId),
      'userName': prefs.getString(_keyUserName),
    };
  }

  /// **Step 1 of OAuth flow.**
  ///
  /// Fetches a request token from Garmin, stores it temporarily, and returns
  /// the authorization URL. Open this URL with [launchAuthorizationUrl] so the
  /// user can authorize the app and receive a PIN.
  Future<String> startAuthentication() async {
    debugPrint('Garmin: requesting OAuth request token…');

    final params = _oauthParams();
    params['oauth_callback'] = 'oob'; // out-of-band → Garmin shows a PIN

    params['oauth_signature'] = _sign('POST', _requestTokenUrl, params, '');

    final response = await http.post(
      Uri.parse(_requestTokenUrl),
      headers: {'Authorization': _authHeader(params)},
    );

    debugPrint('Garmin request token status: ${response.statusCode}');

    if (response.statusCode != 200) {
      throw Exception(
        'Failed to obtain request token (${response.statusCode}): ${response.body}',
      );
    }

    final data = Uri.splitQueryString(response.body);
    final requestToken = data['oauth_token'];
    final requestTokenSecret = data['oauth_token_secret'];

    if (requestToken == null || requestTokenSecret == null) {
      throw Exception('Unexpected Garmin response: ${response.body}');
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyRequestToken, requestToken);
    await prefs.setString(_keyRequestTokenSecret, requestTokenSecret);

    debugPrint('Garmin: request token obtained, ready to authorize.');
    return '$_authorizeUrl?oauth_token=$requestToken';
  }

  /// Opens [url] in the device browser so the user can authorize the app.
  Future<void> launchAuthorizationUrl(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw Exception('Could not open Garmin authorization page.');
    }
  }

  /// **Step 2 of OAuth flow.**
  ///
  /// Exchanges the PIN/verifier the user received from Garmin for permanent
  /// access tokens and stores them via [saveCredentials].
  Future<void> completeAuthentication(String verifier) async {
    debugPrint('Garmin: exchanging verifier for access token…');

    final prefs = await SharedPreferences.getInstance();
    final requestToken = prefs.getString(_keyRequestToken);
    final requestTokenSecret = prefs.getString(_keyRequestTokenSecret) ?? '';

    if (requestToken == null) {
      throw Exception(
        'No pending authorization found. Please start authentication again.',
      );
    }

    final params = _oauthParams();
    params['oauth_token'] = requestToken;
    params['oauth_verifier'] = verifier.trim();

    params['oauth_signature'] = _sign(
      'POST',
      _accessTokenUrl,
      params,
      requestTokenSecret,
    );

    final response = await http.post(
      Uri.parse(_accessTokenUrl),
      headers: {'Authorization': _authHeader(params)},
    );

    debugPrint('Garmin access token status: ${response.statusCode}');

    if (response.statusCode != 200) {
      throw Exception(
        'Token exchange failed (${response.statusCode}): ${response.body}',
      );
    }

    final data = Uri.splitQueryString(response.body);
    final accessToken = data['oauth_token'];
    final accessTokenSecret = data['oauth_token_secret'];
    // Garmin may return userId directly in the access token response
    final userId = data['userId'] ?? data['oauth_token']!;

    if (accessToken == null || accessTokenSecret == null) {
      throw Exception('Invalid access token response: ${response.body}');
    }

    await saveCredentials(
      accessToken: accessToken,
      accessTokenSecret: accessTokenSecret,
      userId: userId,
    );

    // Clean up temporary handshake keys
    await prefs.remove(_keyRequestToken);
    await prefs.remove(_keyRequestTokenSecret);

    debugPrint('Garmin: authentication complete, credentials saved.');
  }

  /// Uploads a FIT file to the Garmin Health API.
  ///
  /// Returns `true` on success (HTTP 200/201/202).
  Future<bool> uploadActivity(String fitFilePath) async {
    debugPrint('Garmin: uploading FIT file → $fitFilePath');

    if (!await isConnected()) {
      throw Exception('Not connected to Garmin. Please authenticate first.');
    }

    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString(_keyAccessToken)!;
    final accessTokenSecret = prefs.getString(_keyAccessTokenSecret)!;
    final userId = prefs.getString(_keyUserId);

    if (userId == null) {
      throw Exception('User ID not found. Please re-authenticate.');
    }

    final uploadUrl = '$_apiBaseUrl/backfill/activity/$userId';

    final params = _oauthParams();
    params['oauth_token'] = accessToken;
    params['oauth_signature'] = _sign(
      'POST',
      uploadUrl,
      params,
      accessTokenSecret,
    );

    final request = http.MultipartRequest('POST', Uri.parse(uploadUrl));
    request.headers['Authorization'] = _authHeader(params);
    request.files.add(await http.MultipartFile.fromPath('file', fitFilePath));

    final streamed = await request.send();
    final body = await streamed.stream.bytesToString();

    debugPrint('Garmin upload status: ${streamed.statusCode}');
    debugPrint('Garmin upload response: $body');

    final success =
        streamed.statusCode == 200 ||
        streamed.statusCode == 201 ||
        streamed.statusCode == 202;

    if (!success) {
      debugPrint('Garmin upload failed: ${streamed.statusCode} $body');
    }

    return success;
  }

  /// Clears all stored Garmin credentials.
  Future<void> disconnect() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyAccessToken);
    await prefs.remove(_keyAccessTokenSecret);
    await prefs.remove(_keyUserId);
    await prefs.remove(_keyUserName);
    await prefs.remove(_keyRequestToken);
    await prefs.remove(_keyRequestTokenSecret);
    debugPrint('Garmin: disconnected, credentials cleared.');
  }

  /// Persists OAuth access credentials to SharedPreferences.
  Future<void> saveCredentials({
    required String accessToken,
    required String accessTokenSecret,
    required String userId,
    String? userName,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyAccessToken, accessToken);
    await prefs.setString(_keyAccessTokenSecret, accessTokenSecret);
    await prefs.setString(_keyUserId, userId);
    if (userName != null) await prefs.setString(_keyUserName, userName);
  }

  /// Opens the Garmin Developer Portal in the browser.
  Future<void> openDeveloperPortal() async {
    const url = 'https://developer.garmin.com/';
    if (!await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    )) {
      throw Exception('Could not open Garmin Developer Portal.');
    }
  }

  // ── OAuth 1.0a helpers ────────────────────────────────────────────────────

  /// Builds the standard OAuth 1.0a parameter map (without signature).
  Map<String, String> _oauthParams() => {
    'oauth_consumer_key': _consumerKey,
    'oauth_signature_method': 'HMAC-SHA1',
    'oauth_timestamp': (DateTime.now().millisecondsSinceEpoch ~/ 1000)
        .toString(),
    'oauth_nonce': _nonce(),
    'oauth_version': '1.0',
  };

  /// Generates a cryptographically random nonce.
  String _nonce() {
    final random = Random.secure();
    return base64Url
        .encode(List<int>.generate(16, (_) => random.nextInt(256)))
        .replaceAll('=', '');
  }

  /// Computes the OAuth 1.0a HMAC-SHA1 signature.
  ///
  /// [method] — HTTP method (uppercase).
  /// [url] — Base URL (no query string).
  /// [params] — All OAuth params (excluding oauth_signature).
  /// [tokenSecret] — Token secret (empty string for request token step).
  String _sign(
    String method,
    String url,
    Map<String, String> params,
    String tokenSecret,
  ) {
    // Percent-encode every key and value, then sort lexicographically by key
    final encoded =
        params.entries.map((e) => MapEntry(_pct(e.key), _pct(e.value))).toList()
          ..sort((a, b) {
            final k = a.key.compareTo(b.key);
            return k != 0 ? k : a.value.compareTo(b.value);
          });

    final paramStr = encoded.map((e) => '${e.key}=${e.value}').join('&');
    final baseString = '${_pct(method)}&${_pct(url)}&${_pct(paramStr)}';
    final signingKey = '${_pct(_consumerSecret)}&${_pct(tokenSecret)}';

    final hmac = Hmac(sha1, utf8.encode(signingKey));
    return base64.encode(hmac.convert(utf8.encode(baseString)).bytes);
  }

  /// Builds the `Authorization: OAuth …` header value.
  String _authHeader(Map<String, String> params) {
    final parts = params.entries
        .where((e) => e.key.startsWith('oauth_'))
        .map((e) => '${e.key}="${_pct(e.value)}"')
        .join(', ');
    return 'OAuth $parts';
  }

  /// RFC 3986 percent-encoding.
  String _pct(String value) => Uri.encodeComponent(value);
}
