import 'package:flutter_test/flutter_test.dart';
import 'package:m6player/services/radio_api.dart';

void main() {
  group('parseStations', () {
    test('parses name, stream URL and country', () {
      final stations = parseStations('''[
        {"name": " Kameme FM ", "url_resolved": "https://example.com/kameme", "country": "Kenya"}
      ]''');

      expect(stations, hasLength(1));
      expect(stations.first.name, 'Kameme FM');
      expect(stations.first.url, 'https://example.com/kameme');
      expect(stations.first.country, 'Kenya');
    });

    test('defaults missing or blank names to Unknown', () {
      final stations = parseStations('''[
        {"url_resolved": "https://example.com/a"},
        {"name": "   ", "url_resolved": "https://example.com/b"}
      ]''');

      expect(stations.map((s) => s.name), ['Unknown', 'Unknown']);
    });

    test('skips stations without a stream URL', () {
      final stations = parseStations('''[
        {"name": "No URL"},
        {"name": "Empty URL", "url_resolved": ""},
        {"name": "Good", "url_resolved": "https://example.com/good"}
      ]''');

      expect(stations.map((s) => s.name), ['Good']);
    });

    test('skips plain-HTTP streams', () {
      final stations = parseStations('''[
        {"name": "Plain", "url_resolved": "http://example.com/plain"},
        {"name": "Secure", "url_resolved": "https://example.com/secure"}
      ]''');

      expect(stations.map((s) => s.name), ['Secure']);
    });

    test('keeps only the first (most popular) entry per stream URL', () {
      final stations = parseStations('''[
        {"name": "Popular", "url_resolved": "https://example.com/same"},
        {"name": "Other", "url_resolved": "https://example.com/other"},
        {"name": "Duplicate", "url_resolved": "https://example.com/same"}
      ]''');

      expect(stations.map((s) => s.name), ['Popular', 'Other']);
    });

    test('handles an empty list', () {
      expect(parseStations('[]'), isEmpty);
    });
  });

  group('parseCountries', () {
    test('keeps countries with a code, a name and stations', () {
      final countries = parseCountries('''[
        {"name": "Kenya", "iso_3166_1": "KE", "stationcount": 42},
        {"name": "", "iso_3166_1": "XX", "stationcount": 3},
        {"name": "Nowhere", "iso_3166_1": "NW", "stationcount": 0}
      ]''');

      expect(countries, hasLength(1));
      expect(countries.first.code, 'KE');
      expect(countries.first.stations, 42);
    });
  });
}
