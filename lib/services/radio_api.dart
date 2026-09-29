import 'dart:convert';
import 'package:http/http.dart' as http;

class RadioStation {
  final String name;
  final String url;
  final String country;

  const RadioStation({required this.name, required this.url, required this.country});
}

/// radio-browser.info's load-balanced host (individual mirrors come and go).
const _apiHost = 'all.api.radio-browser.info';

/// Fetches the most popular working stations for an ISO country code, e.g. "KE".
Future<List<RadioStation>> fetchStations(String countryCode) async {
  final response = await http.get(
    Uri.https(_apiHost, '/json/stations/bycountrycodeexact/$countryCode', {
      'hidebroken': 'true',
      'order': 'clickcount',
      'reverse': 'true',
    }),
    headers: {'User-Agent': 'm6player/1.0'},
  );
  if (response.statusCode != 200) {
    throw http.ClientException('HTTP ${response.statusCode}', response.request?.url);
  }
  return parseStations(response.body);
}

/// Parses a radio-browser station list, skipping stations without a stream URL.
List<RadioStation> parseStations(String body) {
  List<dynamic> data = json.decode(body);
  return data
      .map((station) => RadioStation(
            name: (station["name"] as String?)?.trim().isNotEmpty == true
                ? station["name"].trim()
                : "Unknown",
            url: station["url_resolved"] ?? "",
            country: station["country"] ?? "",
          ))
      .where((station) => station.url.isNotEmpty)
      .toList();
}
