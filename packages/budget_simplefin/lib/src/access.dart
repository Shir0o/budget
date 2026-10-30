import 'dart:convert';

import 'package:budget_core/budget_core.dart';

/// A claimed SimpleFIN access URL (ticket 03).
///
/// It embeds HTTP basic-auth credentials, so it is the long-lived secret:
/// it lives only in this device's secure storage and never reaches core,
/// the store or the Event log (ticket 10).
final class SimpleFinAccess {
  SimpleFinAccess(String value) : uri = Uri.parse(value.trim());

  final Uri uri;

  /// The URL as stored, credentials included. Never log or show it.
  String get value => uri.toString();

  /// Whether [value] reads as an http(s) URL with credentials in it.
  static bool isAccessUrl(String value) {
    final uri = Uri.tryParse(value.trim());
    return uri != null &&
        (uri.isScheme('https') || uri.isScheme('http')) &&
        uri.host.isNotEmpty &&
        uri.userInfo.isNotEmpty;
  }

  /// Where a fetch goes: `<access>/accounts` over [start] to [end], with
  /// `pending=1` so pending charges come too (ticket 03).
  ///
  /// The request URL leaves the credentials out; they travel in
  /// [authorization] instead.
  Uri accountsUri({required CivilDate start, required CivilDate end}) {
    final base = uri.path.replaceAll(RegExp(r'/+$'), '');
    return Uri(
      scheme: uri.scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      path: '$base/accounts',
      queryParameters: {
        ...uri.queryParameters,
        'start-date': '${_startOfDay(start)}',
        'end-date': '${_endOfDay(end)}',
        'pending': '1',
      },
    );
  }

  /// `Basic …` for the credentials in the URL.
  String get authorization =>
      'Basic ${base64Encode(utf8.encode(Uri.decodeComponent(uri.userInfo)))}';

  @override
  String toString() => 'SimpleFinAccess(connected)';

  static int _startOfDay(CivilDate date) =>
      DateTime.utc(date.year, date.month, date.day).millisecondsSinceEpoch ~/
      Duration.millisecondsPerSecond;

  static int _endOfDay(CivilDate date) =>
      DateTime.utc(
            date.year,
            date.month,
            date.day + 1,
          ).millisecondsSinceEpoch ~/
          Duration.millisecondsPerSecond -
      1;
}
