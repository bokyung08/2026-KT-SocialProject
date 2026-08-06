import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../widgets/route_analysis_loading.dart';

class LoadingScreen extends StatelessWidget {
  const LoadingScreen({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: RouteAnalysisLoading(
      responseReady: controller.analysisResponseReady,
      onCancel: controller.cancelAnalysis,
    ),
  );
}
