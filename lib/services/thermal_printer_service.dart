
import 'package:blue_thermal_printer/blue_thermal_printer.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

/// Thin wrapper around [BlueThermalPrinter] — Bluetooth classic (SPP)
/// thermal printers only (the common 58/80mm handheld receipt printers).
///
/// Bills are sent as a rendered bitmap rather than raw ESC/POS text — see
/// [BillScreen] — because these printers can't render Devanagari glyphs from
/// text commands, only from an image.
class ThermalPrinterService {
  ThermalPrinterService._();
  static final ThermalPrinterService instance = ThermalPrinterService._();

  final BlueThermalPrinter _printer = BlueThermalPrinter.instance;

  /// Requests the Bluetooth permissions Android 12+ needs to list/connect to
  /// paired devices. No-op (returns true) on platforms that don't need it.
  Future<bool> ensurePermission() async {
    if (kIsWeb ||
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      return true;
    }
    final statuses = await [
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
    ].request();
    return statuses.values.every((s) => s.isGranted || s.isLimited);
  }

  Future<List<BluetoothDevice>> bondedDevices() async {
    try {
      return await _printer.getBondedDevices();
    } catch (_) {
      return const [];
    }
  }

  Future<bool> get isConnected async {
    try {
      return (await _printer.isConnected) ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> connect(BluetoothDevice device) async {
    try {
      await _printer.connect(device);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> disconnect() async {
    try {
      await _printer.disconnect();
    } catch (_) {
      // already disconnected — nothing to do.
    }
  }

  /// Connects to [address]/[name] if not already connected to that device.
  Future<bool> ensureConnected(String address, String? name) async {
    if (await isConnected) return true;
    return connect(BluetoothDevice(name, address));
  }

  /// Prints a bitmap (a rendered bill) followed by feed lines so the
  /// receipt clears the cutter before the next print.
  Future<bool> printImage(Uint8List pngBytes) async {
    try {
      if (!await isConnected) return false;
      await _printer.printImageBytes(pngBytes);
      await _printer.printNewLine();
      await _printer.printNewLine();
      return true;
    } catch (_) {
      return false;
    }
  }
}
