import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:sj_core/sj_core.dart';

import 'sync.dart';

/// Sync over the local network, no cloud.
///
/// While the app is open it answers on a local port. "Sync now" on the other device finds it by
/// asking the network (a UDP broadcast) or by the address it used last time, then both devices
/// swap packages in one round trip. The packages are the same sealed text as the file and QR
/// transfers (AES-GCM with the key you shared when pairing), so the network never sees journal
/// data and a device without the key cannot get anything or change anything.

const int defaultSyncPort = 47832;
const int defaultDiscoveryPort = 47833;
const String _discoverRequest = 'SJ?';
const String _discoverReply = 'SJ!';

class LanSyncServer {
  LanSyncServer(this.sync, this.deviceId, {this.port = defaultSyncPort, this.discoveryPort = defaultDiscoveryPort, this.bindAddress});

  final SyncService sync;
  final String deviceId;
  final int port;
  final int discoveryPort;
  final InternetAddress? bindAddress;

  HttpServer? _http;
  RawDatagramSocket? _udp;
  Future<void> _busy = Future.value(); // one sync at a time

  int? get httpPort => _http?.port;
  int? get udpPort => _udp?.port;
  bool get running => _http != null;

  /// Starts listening. Never throws: a blocked port just means this device can only start syncs.
  Future<bool> start() async {
    if (_http != null) return true;
    try {
      final address = bindAddress ?? InternetAddress.anyIPv4;
      _http = await _bind(address);
      _http!.listen(_handle, onError: (_) {});
    } on Object {
      _http = null;
      return false;
    }
    try {
      final udp = await RawDatagramSocket.bind(bindAddress ?? InternetAddress.anyIPv4, discoveryPort, reuseAddress: true);
      udp.broadcastEnabled = true;
      udp.listen((event) {
        if (event != RawSocketEvent.read) return;
        final packet = udp.receive();
        if (packet == null) return;
        final text = utf8.decode(packet.data, allowMalformed: true);
        if (text.startsWith(_discoverRequest) && _http != null) {
          udp.send(utf8.encode('$_discoverReply$deviceId|${_http!.port}'), packet.address, packet.port);
        }
      });
      _udp = udp;
    } on Object {
      _udp = null; // discovery is optional; the address fallback still works
    }
    return true;
  }

  Future<HttpServer> _bind(InternetAddress address) async {
    try {
      return await HttpServer.bind(address, port);
    } on SocketException {
      return HttpServer.bind(address, 0); // the usual port is taken: any free one (discovery tells the client)
    }
  }

  Future<void> stop() async {
    await _http?.close(force: true);
    _udp?.close();
    _http = null;
    _udp = null;
  }

  Future<void> _handle(HttpRequest request) async {
    try {
      if (request.method != 'POST' || request.uri.path != '/sj/sync') {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }
      final body = await utf8.decoder.bind(request).join();
      final sender = senderOfPackage(body);
      if (sender == null) {
        request.response
          ..statusCode = HttpStatus.badRequest
          ..write('Not a sync package');
        await request.response.close();
        return;
      }
      final done = Completer<void>();
      final previous = _busy;
      _busy = done.future;
      await previous;
      try {
        await sync.receivePackage(body);
        final reply = await sync.createPackage(sender);
        request.response
          ..statusCode = HttpStatus.ok
          ..write(reply);
      } on SyncException catch (e) {
        request.response
          ..statusCode = HttpStatus.forbidden
          ..write(e.message);
      } finally {
        done.complete();
      }
      await request.response.close();
    } on Object {
      try {
        request.response.statusCode = HttpStatus.internalServerError;
        await request.response.close();
      } on Object {
        // The client has gone.
      }
    }
  }
}

class LanSyncResult {
  const LanSyncResult({required this.peerName, required this.received, required this.address});
  final String peerName;

  /// Changes merged in from the other device.
  final int received;
  final String address;
}

class LanSyncException implements Exception {
  const LanSyncException(this.message);
  final String message;
  @override
  String toString() => message;
}

class LanSyncClient {
  LanSyncClient(this.sync, this.deviceId, {this.discoveryPort = defaultDiscoveryPort, this.discoveryTargets, this.discoveryWait = const Duration(seconds: 3)});

  final SyncService sync;
  final String deviceId;
  final int discoveryPort;

  /// Where to send the "who is there" broadcast (tests point it at loopback).
  final List<InternetAddress>? discoveryTargets;
  final Duration discoveryWait;

  /// Addresses on this network that [peerId] answers from, found by broadcast.
  Future<List<({InternetAddress address, int port})>> discover(String peerId) async {
    final found = <({InternetAddress address, int port})>[];
    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    socket.broadcastEnabled = true;
    final targets = discoveryTargets ?? await _broadcastAddresses();
    final done = Completer<void>();
    socket.listen((event) {
      if (event != RawSocketEvent.read) return;
      final packet = socket.receive();
      if (packet == null) return;
      final text = utf8.decode(packet.data, allowMalformed: true);
      if (!text.startsWith(_discoverReply)) return;
      final parts = text.substring(_discoverReply.length).split('|');
      final port = parts.length == 2 ? int.tryParse(parts[1]) : null;
      if (parts.first == peerId && port != null) {
        found.add((address: packet.address, port: port));
        if (!done.isCompleted) done.complete();
      }
    });
    for (final t in targets) {
      socket.send(utf8.encode('$_discoverRequest$deviceId'), t, discoveryPort);
    }
    await Future.any([done.future, Future<void>.delayed(discoveryWait)]);
    socket.close();
    return found;
  }

  static Future<List<InternetAddress>> _broadcastAddresses() async {
    final result = <InternetAddress>[InternetAddress('255.255.255.255')];
    try {
      for (final iface in await NetworkInterface.list(type: InternetAddressType.IPv4)) {
        for (final a in iface.addresses) {
          final p = a.address.split('.');
          if (p.length == 4) result.add(InternetAddress('${p[0]}.${p[1]}.${p[2]}.255')); // the usual /24
        }
      }
    } on Object {
      // Just the global broadcast.
    }
    return result;
  }

  /// This device's addresses, to show so the other device can be pointed at it by hand.
  static Future<List<String>> localAddresses() async {
    try {
      return [
        for (final iface in await NetworkInterface.list(type: InternetAddressType.IPv4))
          for (final a in iface.addresses)
            if (!a.isLoopback) a.address,
      ];
    } on Object {
      return const [];
    }
  }

  /// One round trip: send what the peer lacks, merge what comes back.
  Future<LanSyncResult> syncWith(String peerId, {String? address, int? port}) async {
    final targets = <({InternetAddress address, int port})>[];
    if (address != null) {
      targets.add((address: InternetAddress(address), port: port ?? defaultSyncPort));
    } else {
      final remembered = await sync.db.getSetting('peerAddr:$peerId');
      if (remembered != null && remembered.contains(':')) {
        final i = remembered.lastIndexOf(':');
        final a = InternetAddress.tryParse(remembered.substring(0, i));
        final p = int.tryParse(remembered.substring(i + 1));
        if (a != null && p != null) targets.add((address: a, port: p));
      }
    }

    Future<LanSyncResult> attempt(InternetAddress a, int p) async {
      final package = await sync.createPackage(peerId);
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 4);
      try {
        final request = await client.postUrl(Uri(scheme: 'http', host: a.address, port: p, path: '/sj/sync')).timeout(const Duration(seconds: 6));
        request.add(utf8.encode(package));
        final response = await request.close().timeout(const Duration(seconds: 60));
        final body = await utf8.decoder.bind(response).join();
        if (response.statusCode == HttpStatus.forbidden) throw LanSyncException(body.isEmpty ? 'The other device did not accept this pairing.' : body);
        if (response.statusCode != HttpStatus.ok) throw const LanSyncException('The other device could not sync right now.');
        final result = await sync.receivePackage(body);
        await sync.db.setSetting('peerAddr:$peerId', '${a.address}:$p');
        return LanSyncResult(peerName: result.peerName, received: result.applied, address: a.address);
      } finally {
        client.close(force: true);
      }
    }

    Object? lastError;
    for (final t in targets) {
      try {
        return await attempt(t.address, t.port);
      } on LanSyncException {
        rethrow;
      } on Object catch (e) {
        lastError = e;
      }
    }
    if (address == null) {
      for (final t in await discover(peerId)) {
        try {
          return await attempt(t.address, t.port);
        } on LanSyncException {
          rethrow;
        } on Object catch (e) {
          lastError = e;
        }
      }
    }
    throw LanSyncException(
      lastError == null
          ? 'Could not find that device on this network. Open Substance Journal on it, make sure both are on the same Wi-Fi, '
              'and allow the app through the firewall if Windows asks.'
          : 'Could not reach that device ($lastError). Check it has the app open on the same Wi-Fi.',
    );
  }
}
