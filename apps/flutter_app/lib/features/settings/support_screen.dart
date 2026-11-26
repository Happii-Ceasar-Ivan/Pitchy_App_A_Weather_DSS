import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/config/donations.dart';
import '../../shared/widgets/pitchy_top_bar.dart';

/// What saving the QR image did.
enum QrSaveResult {
  saved,

  /// Android older than 10: saving needs a storage permission Pitchy doesn't ask for.
  unsupported,
  failed,
}

/// Saves the QR image to the phone's photos, so people can pick it in Maya or
/// their bank app (a phone can't scan its own screen). Own Android code
/// (MediaStore, `MainActivity.kt`), no package, no permission.
abstract interface class QrSaver {
  Future<QrSaveResult> save(Uint8List bytes, String fileName);

  /// The saver for this device, or null where saving isn't offered (Windows:
  /// people scan the screen with their phone).
  static QrSaver? forThisDevice() => !kIsWeb && Platform.isAndroid ? AndroidQrSaver() : null;
}

class AndroidQrSaver implements QrSaver {
  static const _channel = MethodChannel('ph.pitchy.pitchy/media');

  @override
  Future<QrSaveResult> save(Uint8List bytes, String fileName) async {
    try {
      final reply = await _channel.invokeMethod<String>('saveImage', {
        'bytes': bytes,
        'name': fileName,
      });
      return switch (reply) {
        'saved' => QrSaveResult.saved,
        'unsupported' => QrSaveResult.unsupported,
        _ => QrSaveResult.failed,
      };
    } on PlatformException {
      return QrSaveResult.failed;
    }
  }
}

/// Support Pitchy (user, 2026-11-26; P-26): the Maya / QR Ph code as a bundled
/// image, with an honest note. The app never handles, records or verifies
/// money: people pay in Maya or their bank's app.
class SupportScreen extends StatefulWidget {
  const SupportScreen({super.key, required this.qr, this.saver});

  final MayaQr qr;

  /// Null hides "Save QR to Photos".
  final QrSaver? saver;

  @override
  State<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends State<SupportScreen> {
  static const _maxWidth = 560.0;
  bool _saving = false;

  Future<void> _save() async {
    setState(() => _saving = true);
    QrSaveResult result;
    try {
      final data = await rootBundle.load(widget.qr.imageAsset);
      result = await widget.saver!.save(data.buffer.asUint8List(), 'pitchy-maya-qr.jpg');
    } on Exception {
      result = QrSaveResult.failed;
    }
    if (!mounted) return;
    setState(() => _saving = false);
    final message = switch (result) {
      QrSaveResult.saved =>
        'Saved to Photos (Pictures/Pitchy). In Maya or your bank app, upload it from your photos.',
      QrSaveResult.unsupported =>
        'This Android version can’t save it from Pitchy. Take a screenshot instead.',
      QrSaveResult.failed => 'Couldn’t save the QR. Take a screenshot instead.',
    };
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final qr = widget.qr;
    return Scaffold(
      appBar: const PitchyTopBar(title: 'Support Pitchy'),
      body: LayoutBuilder(
        builder: (context, c) {
          final side = ((c.maxWidth - _maxWidth) / 2).clamp(16.0, double.infinity);
          final qrWidth = (c.maxWidth - 2 * side).clamp(200.0, 340.0);
          return ListView(
            padding: EdgeInsets.fromLTRB(side, 20, side, 32),
            children: [
              Text(
                'Pitchy is a student project. Donations help pay for hosting. They’re '
                'optional: the app works the same either way.',
                style: text.bodyLarge,
              ),
              const SizedBox(height: 20),
              // The image carries its own light card, so it scans in every theme.
              Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.asset(
                    qr.imageAsset,
                    width: qrWidth,
                    fit: BoxFit.contain,
                    semanticLabel: 'Maya QR Ph code for ${qr.accountName}',
                  ),
                ),
              ),
              if (widget.saver != null) ...[
                const SizedBox(height: 16),
                Center(
                  child: FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: const Icon(Icons.download),
                    label: Text(_saving ? 'Saving…' : 'Save QR to Photos'),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              for (final note in [
                widget.saver != null
                    ? 'Save it, then upload it in Maya or any bank app that reads QR Ph. '
                          'On another phone, just scan the screen.'
                    : 'Scan it with Maya or any bank app that reads QR Ph.',
                'Before you pay, check that your app shows the name ${qr.accountName}.',
                'Payments go straight to Maya. Pitchy never sees your payment details and '
                    'can’t confirm, refund or record a payment.',
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ExcludeSemantics(child: Text('•  ', style: text.bodyLarge)),
                      Expanded(child: Text(note, style: text.bodyLarge)),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
