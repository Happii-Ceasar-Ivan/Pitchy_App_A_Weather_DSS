/// The team's Maya / QR Ph code for optional donations (user, 2026-11-26: Maya,
/// no PayPal; replaces the Ko-fi plan of P-25). Not a secret: it is what
/// anyone scanning the code sees.
class MayaQr {
  const MayaQr({required this.accountName, required this.imageAsset});

  /// The name Maya or a bank app shows after scanning, so people can check it
  /// before paying.
  final String accountName;

  /// The bundled QR image, e.g. `assets/images/maya_qr.png` (also listed in
  /// pubspec.yaml).
  final String imageAsset;
}

abstract final class Donations {
  /// Supplied by the user on 2026-11-26 (Maya / InstaPay QR Ph). Set to null
  /// to turn Support development back to "Not set up yet".
  // Nullable on purpose: null switches the Settings row off.
  // ignore: unnecessary_nullable_for_final_variable_declarations
  static const MayaQr? maya = MayaQr(
    accountName: 'CEASAR IVAN CAIGA',
    imageAsset: 'assets/images/maya_qr.jpg',
  );
}
