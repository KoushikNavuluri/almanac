import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../state/app_controller.dart';
import '../widgets/common.dart';

/// Connects Health Connect and explains every outcome. Returns true when data is flowing.
Future<bool> connectHealthFlow(BuildContext context) async {
  final app = AppScope.read(context);
  final outcome = await app.connectHealth();
  if (!context.mounted) return false;
  switch (outcome) {
    case ConnectOutcome.connected:
      showToast(context, 'Connected. ${app.insights.nightsWithSleep} nights and ${app.records.fold<int>(0, (s, r) => s + r.meals.length)} meals synced.', good: true);
      return true;
    case ConnectOutcome.needsInstall:
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Health Connect needs installing'),
          content: const Text('Almanac reads your Fitbit and meal data through Google Health Connect. Install or update it from the Play Store, then come back and tap Connect again.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Not now')),
            TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Open Play Store')),
          ],
        ),
      );
      if (ok == true) await app.installHealthConnect();
      return false;
    case ConnectOutcome.unsupported:
      showToast(context, "Health Connect isn't available on this device. You can still explore with sample data.");
      return false;
    case ConnectOutcome.denied:
      showToast(context, 'No access granted. You can allow it any time in Health Connect › App permissions.');
      return false;
    case ConnectOutcome.error:
      showToast(context, app.syncError ?? 'Could not connect to Health Connect.');
      return app.mode == DataMode.healthConnect;
  }
}

/// Writes [text] to a temporary file and opens the system share sheet.
Future<void> shareTextFile(BuildContext context, {required String fileName, required String text, required String mime}) async {
  try {
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}/$fileName');
    await f.writeAsString(text, flush: true);
    await SharePlus.instance.share(ShareParams(files: [XFile(f.path, mimeType: mime)], subject: fileName));
  } catch (e) {
    if (context.mounted) showToast(context, 'Could not open the share sheet ($e)');
  }
}
