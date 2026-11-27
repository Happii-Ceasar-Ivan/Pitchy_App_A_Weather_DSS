// Downloads the official Switzer font files from Fontshare at build time.
//
// Why: Switzer is under the ITF Free Font License (FFL v2.0). Embedding it in
// the app is allowed (§01), but putting the font files in a public repository
// is not (§02), and the files may not be modified (no subsetting, no
// conversion). So the files are git-ignored, fetched unchanged from Fontshare by
// this script on a developer PC or in CI, and bundled into the app as assets.
// The app itself never downloads a font: users' devices never contact
// Fontshare (font privacy rule, P-28).
//
// Usage (from apps/flutter_app):  dart run tool/fetch_switzer.dart [--force]
// Pure Dart; uses only `crypto`, already an app dependency. Skips the download when all four files are present.
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

const kitUrl = 'https://api.fontshare.com/v2/fonts/download/switzer';
// The kit's TTF folder holds only the variable font; the static weights are
// OpenType (CFF) files, which Flutter bundles the same way as TTF.
const entryDir = 'Switzer_Complete/Fonts/OTF/';
const weights = ['Regular', 'Medium', 'Semibold', 'Bold'];

/// SHA-256 of each file as fetched on the first run. A different hash only
/// warns: Fontshare may update the kit, and the font tests re-check it.
const knownSha256 = <String, String>{
  // Recorded 2026-11-27 (kit files dated 2026-11-27).
  'Switzer-Regular.otf': '6208450253b06898c2b58b38d8dab5f6a35059b3fd9b25ab98c5f25cfeeebee7',
  'Switzer-Medium.otf': 'dc1000a1cfd8e9269bd4c26630966e67f9bbb3abe6689aac3d913e99927c6825',
  'Switzer-Semibold.otf': '0b1652d8384fcd5038dc19317ab0e0c4f4b7317e6a9729d8ef38fba375b01921',
  'Switzer-Bold.otf': 'b15598c52907497ac7a014658c335e10f8f6b878ea82c79decd117e926a74b02',
};

Future<void> main(List<String> args) async {
  final force = args.contains('--force');
  final scriptDir = File.fromUri(Platform.script).parent;
  final outDir = Directory('${scriptDir.parent.path}/assets/fonts/switzer');
  final names = [for (final w in weights) 'Switzer-$w.otf'];

  if (!force && names.every((n) => File('${outDir.path}/$n').existsSync())) {
    stdout.writeln('[fonts] Switzer already present, skipping download.');
    return;
  }

  stdout.writeln('[fonts] Downloading Switzer from $kitUrl');
  final zip = await _download(kitUrl);
  final entries = _readZip(zip);

  outDir.createSync(recursive: true);
  for (final name in names) {
    final data = entries['$entryDir$name'];
    if (data == null) {
      _fail(
        '$entryDir$name not found in the Fontshare kit. '
        'OTF entries present: ${entries.keys.where((k) => k.endsWith('.otf')).join(', ')}',
      );
    }
    if (!_isFont(data)) _fail('$name is not a TrueType/OpenType file.');
    File('${outDir.path}/$name').writeAsBytesSync(data, flush: true);
    final sha = sha256.convert(data).toString();
    final known = knownSha256[name];
    final note = known == null
        ? ''
        : known == sha
        ? ' (matches)'
        : ' (WARNING: differs from recorded $known; Fontshare may have updated the kit)';
    stdout.writeln('[fonts] Wrote $name, ${data.length} bytes, sha256 $sha$note');
  }
}

Future<Uint8List> _download(String url) async {
  final client = HttpClient();
  try {
    final req = await client.getUrl(Uri.parse(url));
    final res = await req.close();
    if (res.statusCode != 200) {
      _fail('Fontshare download failed: HTTP ${res.statusCode}');
    }
    final b = BytesBuilder(copy: false);
    await for (final chunk in res) {
      b.add(chunk);
    }
    return b.takeBytes();
  } finally {
    client.close();
  }
}

/// Reads the zip's central directory and returns the OTF entries, inflated.
Map<String, Uint8List> _readZip(Uint8List zip) {
  final v = ByteData.sublistView(zip);
  var eocd = -1;
  for (var i = zip.length - 22; i >= 0; i--) {
    if (v.getUint32(i, Endian.little) == 0x06054b50) {
      eocd = i;
      break;
    }
  }
  if (eocd < 0) _fail('Not a zip archive.');
  final count = v.getUint16(eocd + 10, Endian.little);
  var p = v.getUint32(eocd + 16, Endian.little);
  final out = <String, Uint8List>{};
  for (var i = 0; i < count; i++) {
    if (v.getUint32(p, Endian.little) != 0x02014b50) {
      _fail('Bad zip central directory.');
    }
    final method = v.getUint16(p + 10, Endian.little);
    final compSize = v.getUint32(p + 20, Endian.little);
    final nameLen = v.getUint16(p + 28, Endian.little);
    final extraLen = v.getUint16(p + 30, Endian.little);
    final commentLen = v.getUint16(p + 32, Endian.little);
    final localOffset = v.getUint32(p + 42, Endian.little);
    final name = String.fromCharCodes(zip, p + 46, p + 46 + nameLen);
    if (name.startsWith(entryDir) && name.endsWith('.otf')) {
      final lNameLen = v.getUint16(localOffset + 26, Endian.little);
      final lExtraLen = v.getUint16(localOffset + 28, Endian.little);
      final start = localOffset + 30 + lNameLen + lExtraLen;
      final data = Uint8List.sublistView(zip, start, start + compSize);
      out[name] = switch (method) {
        0 => Uint8List.fromList(data),
        8 => Uint8List.fromList(ZLibDecoder(raw: true).convert(data)),
        _ => _fail('Unsupported zip method $method for $name.'),
      };
    }
    p += 46 + nameLen + extraLen + commentLen;
  }
  return out;
}

bool _isFont(Uint8List d) {
  if (d.length < 4) return false;
  final tag = ByteData.sublistView(d).getUint32(0);
  return tag == 0x00010000 || tag == 0x4f54544f || tag == 0x74727565; // TT, OTTO, true
}

Never _fail(String message) {
  stderr.writeln('[fonts] $message');
  exit(1);
}
