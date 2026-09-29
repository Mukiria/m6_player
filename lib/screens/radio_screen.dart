import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:just_audio/just_audio.dart';

class RadioScreen extends StatefulWidget {
  @override
  _RadioScreenState createState() => _RadioScreenState();
}

class _RadioScreenState extends State<RadioScreen> {
  final AudioPlayer _audioPlayer = AudioPlayer();
  List<Map<String, dynamic>> _radioStations = [];
  List<Map<String, dynamic>> _filteredStations = []; // ✅ For searching
  bool _isLoading = true;
  bool _isPlaying = false;
  String? _currentRadioUrl;
  String _userCountry = "Detecting...";
  TextEditingController _searchController = TextEditingController(); // ✅ Search Controller

  @override
  void initState() {
    super.initState();
    fetchUserLocation();
    _searchController.addListener(_filterStations); // ✅ Add listener for search
  }

  /// ✅ Detect User's Country via IP
  Future<void> fetchUserLocation() async {
    try {
      final locationResponse = await http.get(Uri.parse("http://ip-api.com/json"));
      final locationData = json.decode(locationResponse.body);
      String country = locationData["country"] ?? "USA"; // Default to USA

      setState(() {
        _userCountry = country;
      });

      fetchRadioStations(country);
    } catch (e) {
      print("Error fetching location: $e");
      fetchRadioStations("USA");
    }
  }

  /// ✅ Fetch Radio Stations for the Detected Country
  Future<void> fetchRadioStations(String country) async {
    try {
      String encodedCountry = Uri.encodeComponent(country);
      final response = await http.get(
        Uri.parse("https://nl1.api.radio-browser.info/json/stations/bycountryexact/$encodedCountry"),
      );

      if (response.statusCode == 200) {
        List<dynamic> data = json.decode(response.body);
        if (data.isNotEmpty) {
          setState(() {
            _radioStations = data.map((station) => {
              "name": station["name"] ?? "Unknown",
              "url": station["url_resolved"] ?? "",
            }).toList();
            _filteredStations = _radioStations; // ✅ Set initial list
          });
        } else {
          setState(() {
            _radioStations = [];
            _filteredStations = [];
          });
        }
      } else {
        setState(() {
          _radioStations = [];
          _filteredStations = [];
        });
      }
    } catch (e) {
      print("Error fetching radio stations: $e");
      setState(() {
        _radioStations = [];
        _filteredStations = [];
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// ✅ Search Functionality
  void _filterStations() {
    setState(() {
      _filteredStations = _radioStations
          .where((station) =>
          station["name"].toLowerCase().contains(_searchController.text.toLowerCase()))
          .toList();
    });
  }

  /// ✅ Play or Pause Radio
  Future<void> playRadio(String url) async {
    try {
      print("🎵 Trying to play: $url");

      if (!url.startsWith("https")) {
        print("❌ Skipping non-HTTPS stream: $url");
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Not Available"), backgroundColor: Colors.red),
        );
        return;
      }

      await _audioPlayer.stop();
      await _audioPlayer.setUrl(url);
      await _audioPlayer.play();

      setState(() {
        _currentRadioUrl = url;
        _isPlaying = true;
      });

      print("✅ Now Playing: $url");
    } catch (e) {
      print("❌ Error playing radio: $e");
    }
  }

  Future<void> stopRadio() async {
    await _audioPlayer.stop();
    setState(() {
      _isPlaying = false;
      _currentRadioUrl = null; // ✅ Reset the UI
    });
    print("⏹️ Radio stopped.");
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
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
                padding: EdgeInsets.symmetric(vertical: 20, horizontal: 20),
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
                        Text(
                          "Radio ($_userCountry)",
                          style: TextStyle(
                            fontFamily: "Schyler",
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
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
            ],
          ),

          // ✅ Loading & Radio List
          _isLoading
              ? Center(child: CircularProgressIndicator())
              : _filteredStations.isEmpty
              ? Center(
            child: Text(
              "No radio stations found for $_userCountry.",
              style: TextStyle(color: Colors.white, fontSize: 18),
            ),
          )
              : Positioned(
            top: 180,
            left: 0,
            right: 0,
            bottom: 100,
            child: ListView.builder(
              itemCount: _filteredStations.length,
              itemBuilder: (context, index) {
                return ListTile(
                  title: Text(
                    _filteredStations[index]["name"],
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: Icon(
                          _currentRadioUrl == _filteredStations[index]["url"] && _isPlaying ? Icons.pause : Icons.play_arrow,
                          color: Colors.white,
                        ),
                        onPressed: () => playRadio(_filteredStations[index]["url"]),
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

          // ✅ Stop Button
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 0),
              child: Container(
                width: MediaQuery.of(context).size.width * 1,
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
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
    );
  }
}
