import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/android_update.dart';

/// Optional, non-blocking notice. No network request on Web or other platforms.
class AndroidUpdateNotice extends StatefulWidget {
  const AndroidUpdateNotice({
    super.key,
    required this.child,
    this.check,
    this.openDownload,
  });
  final Widget child;
  final Future<AndroidUpdate?> Function()? check;
  final Future<bool> Function()? openDownload;

  @override
  State<AndroidUpdateNotice> createState() => _AndroidUpdateNoticeState();
}

class _AndroidUpdateNoticeState extends State<AndroidUpdateNotice> {
  AndroidUpdate? _update;
  bool _opening = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _check());
    }
  }

  Future<void> _check() async {
    if (!mounted) return;
    try {
      final update = await (widget.check ?? AndroidUpdateService().check)();
      if (mounted && update != null) setState(() => _update = update);
    } catch (_) {
      // Startup and offline operations remain available on every failure.
    }
  }

  Future<void> _open() async {
    setState(() {
      _opening = true;
      _error = null;
    });
    var opened = false;
    try {
      opened =
          await (widget.openDownload ??
                  () => launchUrl(
                    AndroidUpdate.downloadUrl,
                    mode: LaunchMode.externalApplication,
                  ))()
              .timeout(const Duration(seconds: 5));
    } catch (_) {
      /* Browser unavailable; keep the application usable. */
    }
    if (mounted) {
      setState(() {
        _opening = false;
        if (!opened) {
          _error = 'Impossible d’ouvrir le navigateur. Réessayez plus tard.';
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      if (_update != null)
        Material(
          color: const Color(0xffedf7ed),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: SizedBox(
                width: double.infinity,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Une mise à jour d’Élev’Age est disponible',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Wrap(
                      spacing: 12,
                      children: [
                        TextButton(
                          onPressed: _opening ? null : _open,
                          child: const Text('Télécharger la mise à jour'),
                        ),
                        TextButton(
                          onPressed: () => setState(() => _update = null),
                          child: const Text('Plus tard'),
                        ),
                      ],
                    ),
                    if (_error != null) Text(_error!),
                  ],
                ),
              ),
            ),
          ),
        ),
      Expanded(child: widget.child),
    ],
  );
}
