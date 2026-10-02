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
/// With a [tag] (a genre such as "jazz") only stations with that tag come back;
/// a null [countryCode] then searches the whole world.
Future<List<RadioStation>> fetchStations(String? countryCode, {String? tag}) async {
  Map<String, String> query = {'hidebroken': 'true', 'order': 'clickcount', 'reverse': 'true', 'limit': '500'};
  Uri uri;
  if (tag == null && countryCode != null) {
    uri = Uri.https(_apiHost, '/json/stations/bycountrycodeexact/$countryCode', query);
  } else {
    if (tag != null) query['tag'] = tag;
    if (countryCode != null) query['countrycode'] = countryCode;
    uri = Uri.https(_apiHost, '/json/stations/search', query);
  }
  final response = await http.get(uri, headers: {'User-Agent': 'm6player/1.0'});
  if (response.statusCode != 200) {
    throw http.ClientException('HTTP ${response.statusCode}', response.request?.url);
  }
  return parseStations(response.body);
}

/// Genres offered as quick filters in the Radio tab (radio-browser tags).
const List<String> radioGenres = [
  'pop', 'rock', 'hip hop', 'jazz', 'gospel', 'reggae', 'news', 'talk', 'sports', 'classical', 'electronic', 'country',
];

/// Parses a radio-browser station list into playable stations: only HTTPS
/// streams (plain HTTP is blocked on iOS and Android), one entry per stream
/// URL (the list is sorted by popularity, so the most popular entry is kept).
List<RadioStation> parseStations(String body) {
  List<dynamic> data = json.decode(body);
  Set<String> seenUrls = {};
  return data
      .map((station) => RadioStation(
            name: (station["name"] as String?)?.trim().isNotEmpty == true
                ? station["name"].trim()
                : "Unknown",
            url: station["url_resolved"] ?? "",
            country: station["country"] ?? "",
          ))
      .where((station) => station.url.startsWith("https://") && seenUrls.add(station.url))
      .toList();
}

/// A country radio-browser has stations for.
class RadioCountry {
  final String code; // ISO 3166-1 alpha-2, e.g. "KE"
  final String name;
  final int stations;

  const RadioCountry({required this.code, required this.name, required this.stations});
}

/// Every country with stations, A to Z.
Future<List<RadioCountry>> fetchCountries() async {
  final response = await http.get(
    Uri.https(_apiHost, '/json/countries', {'hidebroken': 'true', 'order': 'name'}),
    headers: {'User-Agent': 'm6player/1.0'},
  );
  if (response.statusCode != 200) {
    throw http.ClientException('HTTP ${response.statusCode}', response.request?.url);
  }
  return parseCountries(response.body);
}

List<RadioCountry> parseCountries(String body) {
  List<dynamic> data = json.decode(body);
  return data
      .map((c) => RadioCountry(
            code: (c['iso_3166_1'] as String?) ?? '',
            name: (c['name'] as String?)?.trim() ?? '',
            stations: (c['stationcount'] as num?)?.toInt() ?? 0,
          ))
      .where((c) => c.code.length == 2 && c.name.isNotEmpty && c.stations > 0)
      .toList();
}
