import 'package:flutter/material.dart';

import 'app_controller.dart';
import 'screens/home_screen.dart';
import 'screens/info_screen.dart';
import 'screens/loading_screen.dart';
import 'screens/route_input_screen.dart';
import 'screens/route_result_screen.dart';
import 'theme/app_theme.dart';

class SafeLineApp extends StatefulWidget {
  const SafeLineApp({super.key});
  @override
  State<SafeLineApp> createState() => _SafeLineAppState();
}

class _SafeLineAppState extends State<SafeLineApp> {
  late final AppController controller;
  @override
  void initState() {
    super.initState();
    controller = AppController()..addListener(_changed);
  }

  void _changed() => setState(() {});
  @override
  void dispose() {
    controller.removeListener(_changed);
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'PM 세이프라인',
    theme: buildAppTheme(),
    home: ColoredBox(
      color: const Color(0xFFECECEF),
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: _screen(),
          ),
        ),
      ),
    ),
  );
  Widget _screen() => switch (controller.screen) {
    AppScreen.home => HomeScreen(controller: controller),
    AppScreen.input => RouteInputScreen(controller: controller),
    AppScreen.loading => LoadingScreen(controller: controller),
    AppScreen.result => RouteResultScreen(controller: controller),
    AppScreen.info => InfoScreen(controller: controller),
  };
}
