import 'dart:async';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import '../services/player_service.dart';
import '../services/radio_api.dart';
import '../widgets/app_logo.dart';
import '../widgets/app_menu.dart';
import '../widgets/artwork.dart';
import '../widgets/tab_background.dart';

/// The Radio tab: popular stations for the phone's country, with search.
class RadioScreen extends StatefulWidget {
  const RadioScreen({super.key});

  @override
  State<RadioScreen> createState() => _RadioScreenState();
}

class _RadioScreenState extends State<RadioScreen> {
  final PlayerService _service = PlayerService.instance;
  AudioPlayer get _audioPlayer => _service.player;
  StreamSubscription? _playerStateSubscription;

  List<RadioStation> _radioStations = [];
  List<RadioStation> _filteredStations = []; // ✅ For searching
  bool _isLoading = true;
  bool _loadFailed = false; // Network/server error, as opposed to "no stations"
  bool _isPlaying = false;
  String? _currentRadioUrl;
  String _userCountry = "Detecting...";
  final TextEditingController _searchController = TextEditingController(); // ✅ Search Controller

  @override
  void initState() {
    super.initState();
    _playerStateSubscription = _audioPlayer.playerStateStream.listen((state) {
      setState(() => _isPlaying = state.playing);
    });
    fetchRadioStations(_deviceCountryCode());
    _searchController.addListener(_filterStations); // ✅ Add listener for search
  }

  /// ✅ The user's country from the device's region setting (no network lookup).
  String _deviceCountryCode() {
    String? code = WidgetsBinding.instance.platformDispatcher.locale.countryCode;
    return (code == null || code.isEmpty) ? "US" : code.toUpperCase();
  }

  /// ✅ Fetch Radio Stations for the user's country
  Future<void> fetchRadioStations(String countryCode) async {
    // Already loading on first run (called from initState, where setState isn't allowed)
    if (!_isLoading) {
      setState(() {
        _isLoading = true;
        _loadFailed = false;
      });
    }
    List<RadioStation> stations = [];
    bool failed = false;
    try {
      stations = await fetchStations(countryCode);
    } catch (e) {
      debugPrint("Error fetching radio stations: $e");
      failed = true;
    }
    if (!mounted) return;
    setState(() {
      _radioStations = stations;
      _loadFailed = failed;
      _userCountry = stations.isNotEmpty && stations.first.country.isNotEmpty
          ? stations.first.country
          : countryCode;
      _isLoading = false;
    });
    _filterStations();
  }

  /// ✅ Search Functionality
  void _filterStations() {
    String query = _searchController.text.toLowerCase();
    setState(() {
      _filteredStations = _radioStations
          .where((station) => station.name.toLowerCase().contains(query))
          .toList();
    });
  }

  /// ✅ Play or Pause Radio
  Future<void> playRadio(RadioStation station) async {
    if (_currentRadioUrl == station.url && !_service.isLibraryActive) {
      if (_isPlaying) {
        await _audioPlayer.pause();
      } else {
        _audioPlayer.play();
      }
      return;
    }

    setState(() => _currentRadioUrl = station.url);
    try {
      await _service.playStream(station.url, station.name);
    } catch (e) {
      debugPrint("Error playing radio: $e");
      if (!mounted) return;
      setState(() => _currentRadioUrl = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Couldn't play ${station.name}"), backgroundColor: Colors.red),
      );
    }
  }

  @override
  void dispose() {
    // The player is shared and keeps playing in the background; just stop listening.
    _playerStateSubscription?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ColorScheme colors = Theme.of(context).colorScheme;
    return TabBackground(
      image: 'assets/backgrounds/radio.jpg',
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: AppLogo(),
          centerTitle: false,
          actions: const [AppMenuButton()],
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: SearchBar(
                controller: _searchController,
                hintText: "Search stations",
                leading: Icon(Icons.search),
                elevation: WidgetStatePropertyAll(0),
                backgroundColor: WidgetStatePropertyAll(colors.surfaceContainerHighest),
              ),
            ),
            if (!_isLoading && !_loadFailed)
              Padding(
                padding: EdgeInsets.fromLTRB(16, 4, 16, 4),
                child: Text("Stations in $_userCountry (${_filteredStations.length})",
                    style: TextStyle(fontSize: 13, color: colors.onSurfaceVariant)),
              ),
            Expanded(
              child: _isLoading
                  ? Center(child: CircularProgressIndicator())
                  : _loadFailed
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.wifi_off, size: 48, color: colors.onSurfaceVariant),
                              SizedBox(height: 12),
                              Text(
                                "Couldn't load radio stations.\nCheck your internet connection.",
                                textAlign: TextAlign.center,
                              ),
                              SizedBox(height: 16),
                              FilledButton.icon(
                                onPressed: () => fetchRadioStations(_deviceCountryCode()),
                                icon: Icon(Icons.refresh),
                                label: Text("Retry"),
                              ),
                            ],
                          ),
                        )
                      : _filteredStations.isEmpty
                          ? Center(child: Text("No radio stations found for $_userCountry."))
                          : ListView.builder(
                              itemCount: _filteredStations.length,
                              itemBuilder: (context, index) => _stationTile(_filteredStations[index], colors),
                            ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stationTile(RadioStation station, ColorScheme colors) {
    bool isCurrent = _currentRadioUrl == station.url && !_service.isLibraryActive;
    return ListTile(
      leading: Artwork(size: 40, isRadio: true, round: true),
      title: Text(
        station.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: isCurrent ? colors.primary : null,
          fontWeight: isCurrent ? FontWeight.w600 : null,
        ),
      ),
      trailing: isCurrent
          ? Icon(_isPlaying ? Icons.graphic_eq : Icons.pause, color: colors.primary)
          : null,
      onTap: () => playRadio(station),
    );
  }
}
