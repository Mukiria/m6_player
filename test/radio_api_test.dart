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

    test('handles an empty list', () {
      expect(parseStations('[]'), isEmpty);
    });
  });
}
