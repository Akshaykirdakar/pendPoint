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

  // ---- Inventory alerts (spec §27N — configurable thresholds/toggles) ----
  bool expiryAlertsOn;
  int nearExpiryDays; // "Near Expiry" — default 30
  int expirySoonDays; // "Expiry Soon" — default 15
  int criticalExpiryDays; // "Critical Expiry" — default 7
  bool lowStockAlertsOn;
  bool outOfStockAlertsOn;
  bool batchAlertsOn;

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
    this.expiryAlertsOn = true,
    this.nearExpiryDays = 30,
    this.expirySoonDays = 15,
    this.criticalExpiryDays = 7,
    this.lowStockAlertsOn = true,
    this.outOfStockAlertsOn = true,
    this.batchAlertsOn = true,
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
        expiryAlertsOn: expiryAlertsOn,
        nearExpiryDays: nearExpiryDays,
        expirySoonDays: expirySoonDays,
        criticalExpiryDays: criticalExpiryDays,
        lowStockAlertsOn: lowStockAlertsOn,
        outOfStockAlertsOn: outOfStockAlertsOn,
        batchAlertsOn: batchAlertsOn,
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
        'expiryAlertsOn': expiryAlertsOn,
        'nearExpiryDays': nearExpiryDays,
        'expirySoonDays': expirySoonDays,
        'criticalExpiryDays': criticalExpiryDays,
        'lowStockAlertsOn': lowStockAlertsOn,
        'outOfStockAlertsOn': outOfStockAlertsOn,
        'batchAlertsOn': batchAlertsOn,
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
        expiryAlertsOn: (m['expiryAlertsOn'] ?? true) as bool,
        nearExpiryDays: (m['nearExpiryDays'] ?? 30) as int,
        expirySoonDays: (m['expirySoonDays'] ?? 15) as int,
        criticalExpiryDays: (m['criticalExpiryDays'] ?? 7) as int,
        lowStockAlertsOn: (m['lowStockAlertsOn'] ?? true) as bool,
        outOfStockAlertsOn: (m['outOfStockAlertsOn'] ?? true) as bool,
        batchAlertsOn: (m['batchAlertsOn'] ?? true) as bool,
      );
}
