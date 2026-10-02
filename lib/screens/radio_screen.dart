import 'dart:async';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import '../services/app_settings.dart';
import '../services/library_store.dart';
import '../services/player_service.dart';
import '../services/radio_api.dart';
import '../widgets/app_logo.dart';
import '../widgets/app_menu.dart';
import '../widgets/artwork.dart';
import '../widgets/tab_background.dart';

/// Which stations the Radio tab lists.
enum _RadioView { stations, favourites, recent }

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
  LibraryStore? _store;
  _RadioView _view = _RadioView.stations;
  String? _genre; // A genre chip picked, e.g. "jazz"
  bool _worldwide = false; // Genre search across all countries
  String _userCountry = "Detecting...";
  final TextEditingController _searchController = TextEditingController(); // ✅ Search Controller

  @override
  void initState() {
    super.initState();
    _playerStateSubscription = _audioPlayer.playerStateStream.listen((state) {
      setState(() => _isPlaying = state.playing);
    });
    LibraryStore.instance().then((store) {
      if (!mounted) return;
      store.addListener(_filterStations);
      _store = store;
      _filterStations();
    }).catchError((Object e) => debugPrint("Error opening the library store: $e"));
    fetchRadioStations(_deviceCountryCode());
    _searchController.addListener(_filterStations); // ✅ Add listener for search
  }

  /// ✅ The user's country from the device's region setting (no network lookup).
  String _deviceCountryCode() {
    String? saved = AppSettings.instance.radioCountry;
    if (saved != null) return saved;
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
      stations = await fetchStations(_genre != null && _worldwide ? null : countryCode, tag: _genre);
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

  void _setView(_RadioView view) {
    _view = view;
    _filterStations();
  }

  String get _heading {
    int count = _filteredStations.length;
    switch (_view) {
      case _RadioView.favourites:
        return "Favourite stations ($count)";
      case _RadioView.recent:
        return "Recently played ($count)";
      case _RadioView.stations:
        if (_loadFailed) return "";
        String genre = _genre == null ? "Stations" : "${_genre![0].toUpperCase()}${_genre!.substring(1)} stations";
        return "$genre ${_genre != null && _worldwide ? "worldwide" : "in $_userCountry"} ($count)";
    }
  }

  String get _emptyText {
    switch (_view) {
      case _RadioView.favourites:
        return "No favourite stations yet.\nTap the heart on a station to add it.";
      case _RadioView.recent:
        return "Nothing played yet.\nStations you listen to show up here.";
      case _RadioView.stations:
        return _genre == null
            ? "No radio stations found for $_userCountry."
            : "No $_genre stations found${_worldwide ? "" : " in $_userCountry.\nTry Worldwide"}.";
    }
  }

  /// Lets the user pick another country's stations (or go back to the phone's region).
  Future<void> _chooseCountry() async {
    String? picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => _CountryPicker(current: _deviceCountryCode()),
    );
    if (picked == null) return;
    // "" means back to the phone's own region
    await AppSettings.instance.setRadioCountry(picked.isEmpty ? null : picked);
    _searchController.clear();
    fetchRadioStations(_deviceCountryCode());
  }

  /// ✅ Search Functionality
  void _filterStations() {
    String query = _searchController.text.toLowerCase();
    setState(() {
      _filteredStations = (switch (_view) {
        _RadioView.favourites => _store?.radioFavourites ?? [],
        _RadioView.recent => _store?.radioRecent ?? [],
        _RadioView.stations => _radioStations,
      })
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
      _store?.addRadioRecent(station);
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
    _store?.removeListener(_filterStations);
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
          actions: [
            IconButton(tooltip: "Change country", icon: Icon(Icons.public), onPressed: _chooseCountry),
            const SearchButton(),
            const AppMenuButton(),
          ],
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
            if (!_isLoading) ...[
              Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 0),
                child: Row(
                  children: [
                    Expanded(child: Text(_heading, style: TextStyle(fontSize: 13, color: colors.onSurfaceVariant))),
                    FilterChip(
                      label: Text("Recent"),
                      avatar: Icon(Icons.history, size: 16),
                      selected: _view == _RadioView.recent,
                      onSelected: (on) => _setView(on ? _RadioView.recent : _RadioView.stations),
                    ),
                    SizedBox(width: 6),
                    FilterChip(
                      label: Text("Favourites"),
                      avatar: Icon(Icons.favorite, size: 16),
                      selected: _view == _RadioView.favourites,
                      onSelected: (on) => _setView(on ? _RadioView.favourites : _RadioView.stations),
                    ),
                  ],
                ),
              ),
              if (_view == _RadioView.stations)
                SizedBox(
                  height: 44,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    children: [
                      if (_genre != null)
                        Padding(
                          padding: EdgeInsets.only(right: 6),
                          child: FilterChip(
                            label: Text("Worldwide"),
                            avatar: Icon(Icons.public, size: 16),
                            selected: _worldwide,
                            onSelected: (on) {
                              _worldwide = on;
                              fetchRadioStations(_deviceCountryCode());
                            },
                          ),
                        ),
                      for (String genre in radioGenres)
                        Padding(
                          padding: EdgeInsets.only(right: 6),
                          child: ChoiceChip(
                            label: Text(genre),
                            selected: _genre == genre,
                            onSelected: (on) {
                              _genre = on ? genre : null;
                              if (!on) _worldwide = false;
                              fetchRadioStations(_deviceCountryCode());
                            },
                          ),
                        ),
                    ],
                  ),
                ),
            ],
            Expanded(
              child: _isLoading
                  ? Center(child: CircularProgressIndicator())
                  : _loadFailed && _view == _RadioView.stations
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
                          ? Center(
                              child: Text(_emptyText, textAlign: TextAlign.center))
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
    bool favourite = _store?.isRadioFavourite(station.url) ?? false;
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
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isCurrent) Icon(_isPlaying ? Icons.graphic_eq : Icons.pause, color: colors.primary),
          IconButton(
            tooltip: favourite ? "Remove from favourites" : "Add to favourites",
            icon: Icon(favourite ? Icons.favorite : Icons.favorite_border, color: favourite ? colors.primary : null),
            onPressed: () => _store?.toggleRadioFavourite(station),
          ),
        ],
      ),
      onTap: () => playRadio(station),
    );
  }
}

/// Bottom sheet listing every country with stations, searchable. Pops the
/// chosen ISO code, or "" for the phone's own region.
class _CountryPicker extends StatefulWidget {
  final String current;

  const _CountryPicker({required this.current});

  @override
  State<_CountryPicker> createState() => _CountryPickerState();
}

class _CountryPickerState extends State<_CountryPicker> {
  List<RadioCountry>? _countries;
  bool _failed = false;
  String _query = '';

  @override
  void initState() {
    super.initState();
    fetchCountries().then((countries) {
      if (mounted) setState(() => _countries = countries);
    }).catchError((Object e) {
      debugPrint("Error fetching countries: $e");
      if (mounted) setState(() => _failed = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    List<RadioCountry>? countries = _countries;
    List<RadioCountry> shown =
        countries?.where((c) => c.name.toLowerCase().contains(_query)).toList() ?? [];
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.8,
      child: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              decoration: InputDecoration(prefixIcon: Icon(Icons.search), hintText: "Search countries"),
              onChanged: (text) => setState(() => _query = text.trim().toLowerCase()),
            ),
          ),
          ListTile(
            leading: Icon(Icons.phone_android),
            title: Text("Use my phone's region"),
            onTap: () => Navigator.pop(context, ''),
          ),
          Expanded(
            child: _failed
                ? Center(child: Text("Couldn't load the countries.\nCheck your internet connection.", textAlign: TextAlign.center))
                : countries == null
                    ? Center(child: CircularProgressIndicator())
                    : ListView.builder(
                        itemCount: shown.length,
                        itemBuilder: (context, index) => ListTile(
                          title: Text(shown[index].name),
                          subtitle: Text("${shown[index].stations} stations"),
                          selected: shown[index].code == widget.current,
                          onTap: () => Navigator.pop(context, shown[index].code),
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}
