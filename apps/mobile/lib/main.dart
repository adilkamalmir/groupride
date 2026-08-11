import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/auth_screen.dart';
import 'screens/home_screen.dart';
import 'services/api_client.dart';
import 'services/auth_service.dart';
import 'services/location_service.dart';
import 'services/maps_service.dart';
import 'services/ride_realtime_service.dart';
import 'services/ride_service.dart';
import 'theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const GroupRideApp());
}

class GroupRideApp extends StatefulWidget {
  const GroupRideApp({super.key});

  @override
  State<GroupRideApp> createState() => _GroupRideAppState();
}

class _GroupRideAppState extends State<GroupRideApp> {
  late final ApiClient _api;
  late final AuthService _auth;
  late final RideService _rides;
  late final MapsService _maps;
  late final RideRealtimeService _realtime;
  late final LocationService _location;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _api = ApiClient();
    _auth = AuthService(_api);
    _rides = RideService(_api);
    _maps = MapsService(_api);
    _realtime = RideRealtimeService();
    _location = LocationService();
    _auth.restore().whenComplete(() {
      if (mounted) setState(() => _ready = true);
    });
  }

  @override
  void dispose() {
    _api.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: _auth),
        Provider.value(value: _rides),
        Provider.value(value: _maps),
        ChangeNotifierProvider.value(value: _realtime),
        ChangeNotifierProvider.value(value: _location),
      ],
      child: MaterialApp(
        title: 'GroupRide',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark,
        home: !_ready
            ? const Scaffold(body: Center(child: CircularProgressIndicator()))
            : Consumer<AuthService>(
                builder: (context, auth, _) {
                  return auth.isAuthenticated ? const HomeScreen() : const AuthScreen();
                },
              ),
      ),
    );
  }
}
