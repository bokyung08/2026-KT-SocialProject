import 'package:flutter/material.dart';

import 'app.dart';
import 'config/api_config.dart';

void main() {
  ApiConfig.logStartup();
  runApp(const SafeLineApp());
}
