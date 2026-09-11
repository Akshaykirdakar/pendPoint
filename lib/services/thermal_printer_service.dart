import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:permission_handler/permission_handler.dart';
import 'package:unified_esc_pos_printer/unified_esc_pos_printer.dart';

/// Thin wrapper around [PrinterManager] — Bluetooth classic (SPP) thermal
/// printers only (the common 58mm handheld receipt printers this shop uses).
///
/// Bills are sent as a rendered bitmap rather than raw ESC/POS text — see
/// [BillScreen] — because these printers can't render Devanagari glyphs from
/// text commands, only from an image.
///
/// (Previously wrapped `blue_thermal_printer`, which is unmaintained and
/// fails to build under modern Android Gradle Plugin versions — its bundled
/// AndroidManifest still declares a legacy `package=` attribute that AGP 8+
/// rejects outright, with no workaround short of patching the dependency
/// itself. `unified_esc_pos_printer` is actively maintained and supports the
/// same Bluetooth Classic + image-raster printing this app needs.)
class ThermalPrinterService {
  ThermalPrinterService._();
  static final ThermalPrinterService instance = ThermalPrinterService._();

  final PrinterManager _manager = PrinterManager();

  /// Requests the permissions Android needs to discover/connect to
  /// Bluetooth Classic devices: BLUETOOTH_CONNECT/SCAN on Android 12+, plus
  /// location (required by Android ≤11 for Bluetooth discovery to return
  /// any results). No-op (returns true) on platforms that don't need it.
  Future<bool> ensurePermission() async {
    if (kIsWeb ||
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      return true;
    }
    final statuses = await [
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
      Permission.locationWhenInUse,
    ].request();
    return statuses.values.every((s) => s.isGranted || s.isLimited);
  }

  /// Discovers nearby/paired Bluetooth Classic printers.
  Future<List<BluetoothPrinterDevice>> discoverDevices(
      {Duration timeout = const Duration(seconds: 5)}) async {
    try {
      final found = await _manager.scanPrinters(
        types: {PrinterConnectionType.bluetooth},
        timeout: timeout,
      );
      return found.whereType<BluetoothPrinterDevice>().toList();
    } catch (_) {
      return const [];
    }
  }

  bool get isConnected => _manager.isConnected;

  Future<bool> connect(BluetoothPrinterDevice device) async {
    try {
      await _manager.connect(device);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> disconnect() async {
    try {
      await _manager.disconnect();
    } catch (_) {
      // already disconnected — nothing to do.
    }
  }

  /// Connects to [address]/[name] if not already connected to that device.
  Future<bool> ensureConnected(String address, String? name) async {
    if (isConnected) return true;
    return connect(
        BluetoothPrinterDevice(name: name ?? 'Printer', address: address));
  }

  /// Prints a bitmap (a rendered bill) via ESC/POS raster mode, then cuts.
  /// Sized for the common 58mm/384-dot printer this shop uses — for an
  /// 80mm printer, switch [PaperSize.mm58] to [PaperSize.mm80] and
  /// `maxWidth` to 576.
  Future<bool> printImage(Uint8List pngBytes) async {
    try {
      if (!isConnected) return false;
      final image = img.decodeImage(pngBytes);
      if (image == null) return false;
      final ticket = await Ticket.create(PaperSize.mm58);
      ticket.imageRaster(image, align: PrintAlign.center, maxWidth: 384);
      ticket.cut();
      await _manager.printTicket(ticket);
      return true;
    } catch (_) {
      return false;
    }
  }
}
