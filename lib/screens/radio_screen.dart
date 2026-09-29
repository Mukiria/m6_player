import 'dart:async';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import '../services/player_service.dart';
import '../services/radio_api.dart';

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
    List<RadioStation> stations = [];
    try {
      stations = await fetchStations(countryCode);
    } catch (e) {
      debugPrint("Error fetching radio stations: $e");
    }
    if (!mounted) return;
    setState(() {
      _radioStations = stations;
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

    // iOS and Android both block plain-HTTP streams
    if (!station.url.startsWith("https")) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Not Available"), backgroundColor: Colors.red),
      );
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

  Future<void> stopRadio() async {
    await _service.stop();
    if (!mounted) return;
    setState(() => _currentRadioUrl = null); // ✅ Reset the UI
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
    return Scaffold(
      extendBodyBehindAppBar: true,

      body: Stack(
        children: [
          // ✅ Background Image
          Container(
            decoration: BoxDecoration(
              image: DecorationImage(
                image: AssetImage("assets/splash-screen-radio.jpg"),
                fit: BoxFit.cover,
              ),
            ),
          ),

          // ✅ Top Bar with Search Box
          Column(
            children: [
              Container(
                width: double.infinity,
                // Extended up behind the status bar
                padding: EdgeInsets.fromLTRB(20, MediaQuery.of(context).padding.top + 20, 20, 20),
                decoration: BoxDecoration(
                  color: Color(0xFFA20CA2),
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(20),
                    bottomRight: Radius.circular(20),
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        IconButton(
                          icon: Icon(Icons.arrow_back, color: Colors.white),
                          onPressed: () {
                            Navigator.pop(context);
                          },
                        ),
                        SizedBox(width: 10),
                        Image.asset(
                          "assets/logo.png",
                          height: 60,
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            "Radio ($_userCountry)",
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: "Schyler",
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 10),
                    // ✅ Search Bar
                    TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: "Search for a station...",
                        filled: true,
                        fillColor: Colors.white,
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // ✅ Loading & Radio List
              Expanded(
                child: _isLoading
                    ? Center(child: CircularProgressIndicator())
                    : _filteredStations.isEmpty
                        ? Center(
                            child: Text(
                              "No radio stations found for $_userCountry.",
                              style: TextStyle(color: Colors.white, fontSize: 18),
                            ),
                          )
                        : ListView.builder(
                            padding: EdgeInsets.zero,
                            itemCount: _filteredStations.length,
                            itemBuilder: (context, index) {
                              RadioStation station = _filteredStations[index];
                              bool isCurrent = _currentRadioUrl == station.url && !_service.isLibraryActive;
                              return ListTile(
                                title: Text(
                                  station.name,
                                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: Icon(
                                        isCurrent && _isPlaying ? Icons.pause : Icons.play_arrow,
                                        color: Colors.white,
                                      ),
                                      onPressed: () => playRadio(station),
                                    ),
                                    IconButton(
                                      icon: Icon(Icons.stop, color: Colors.red),
                                      onPressed: stopRadio, // ✅ Stop button added
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
              ),

              // ✅ Stop Button, extended down behind the navigation bar
              Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 0),
                  child: Container(
                    width: MediaQuery.of(context).size.width * 1,
                    padding: EdgeInsets.fromLTRB(20, 10, 20, MediaQuery.of(context).padding.bottom + 10),
                    decoration: BoxDecoration(
                      color: Color(0xFFA20CA2),
                    ),
                    child: IconButton(
                      icon: Icon(Icons.stop, color: Colors.white, size: 30),
                      onPressed: stopRadio,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
