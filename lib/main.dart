import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app.dart';
import 'state/app_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Fonts are fetched once from Google Fonts and cached; no health data is involved.
  GoogleFonts.config.allowRuntimeFetching = true;
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(statusBarColor: Colors.transparent));
  final controller = AppController();
  runApp(AlmanacApp(controller: controller));
  await controller.init();
}
