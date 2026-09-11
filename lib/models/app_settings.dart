/// Shop-wide settings.
enum AppLang { mr, both, en }

enum AppThemeMode { system, light, dark }

class AppSettings {
  String shop;
  AppLang lang;
  AppThemeMode theme;
  int lowDefaultBags;
  bool floorOn; // enforce per-product price floor
  bool gateOverride; // require Owner PIN for large discounts
  double gateOverridePct; // discount % above which PIN is required
  String? printerName; // paired Bluetooth thermal printer (display name)
  String? printerAddress; // ...and its MAC address, used to reconnect

  AppSettings({
    this.shop = 'जय किसान पेंड भांडार',
    this.lang = AppLang.both,
    this.theme = AppThemeMode.system,
    this.lowDefaultBags = 5,
    this.floorOn = true,
    this.gateOverride = true,
    this.gateOverridePct = 5,
    this.printerName,
    this.printerAddress,
  });

  AppSettings copy() => AppSettings(
        shop: shop,
        lang: lang,
        theme: theme,
        lowDefaultBags: lowDefaultBags,
        floorOn: floorOn,
        gateOverride: gateOverride,
        gateOverridePct: gateOverridePct,
        printerName: printerName,
        printerAddress: printerAddress,
      );

  Map<String, dynamic> toMap() => {
        'shop': shop,
        'lang': lang.name,
        'theme': theme.name,
        'lowDefaultBags': lowDefaultBags,
        'floorOn': floorOn,
        'gateOverride': gateOverride,
        'gateOverridePct': gateOverridePct,
        'printerName': printerName,
        'printerAddress': printerAddress,
      };

  factory AppSettings.fromMap(Map<String, dynamic> m) => AppSettings(
        shop: (m['shop'] ?? 'जय किसान पेंड भांडार') as String,
        lang: AppLang.values
            .firstWhere((l) => l.name == m['lang'], orElse: () => AppLang.both),
        theme: AppThemeMode.values.firstWhere((t) => t.name == m['theme'],
            orElse: () => AppThemeMode.system),
        lowDefaultBags: (m['lowDefaultBags'] ?? 5) as int,
        floorOn: (m['floorOn'] ?? true) as bool,
        gateOverride: (m['gateOverride'] ?? true) as bool,
        gateOverridePct: (m['gateOverridePct'] ?? 5).toDouble(),
        printerName: m['printerName'] as String?,
        printerAddress: m['printerAddress'] as String?,
      );
}
