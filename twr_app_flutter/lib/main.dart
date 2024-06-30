import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:provider/provider.dart';
import 'package:twr_app_flutter/screens/joystick_screen.dart';
import 'models/screen_model.dart';
import 'screens/testing_screen.dart';

void main() {
  FlutterBluePlus.setLogLevel(LogLevel.none, color: true);

  // Prevent landscape
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  runApp(
    ChangeNotifierProvider(
      create: (context) => ScreenModel(),
      child: const TWRApp(),
    ),
  );
}

class TWRApp extends StatelessWidget {
  const TWRApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'twr-app',
        theme: ThemeData(
          // This is the theme of your application.
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.orangeAccent),
          useMaterial3: false,
        ),
        home: DefaultTabController(
          length: 2,
          child: Scaffold(
            appBar: AppBar(
              toolbarHeight: 0,
              bottom: const TabBar(
                tabs: [
                  Tab(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.gamepad),
                        SizedBox(width: 8),
                        Text('Joystick'),
                      ],
                    ),
                  ),
                  Tab(
                      child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.science),
                      SizedBox(width: 8),
                      Text('Testing'),
                    ],
                  )),
                ],
              ),
            ),
            body: const TabBarView(
                // NeverScrollableScrollPhysics needed to disable swiping
                // between tabs, in favor of the joystick
                physics: NeverScrollableScrollPhysics(),
                children: [
                  JoystickScreen(),
                  TestingScreen(),
                ]),
          ),
        ));
  }
}
