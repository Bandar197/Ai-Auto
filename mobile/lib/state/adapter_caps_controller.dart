import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../obd/obd.dart';
import 'connection_controller.dart';

/// Why a capability probe could not start.
enum ProbeBlock { noAdapter, replay, busy }

class ProbeBlockedException implements Exception {
  const ProbeBlockedException(this.reason);
  final ProbeBlock reason;
  @override
  String toString() => 'ProbeBlockedException($reason)';
}

/// Proven capabilities of the adapter on the current connection. `data(null)` =
/// not probed yet; it resets whenever the connection (client) changes, so a result
/// from one adapter is never shown for another.
class AdapterCapsController extends Notifier<AsyncValue<AdapterCapabilities?>> {
  @override
  AsyncValue<AdapterCapabilities?> build() {
    ref.watch(connectionProvider.select((s) => s.client));
    return const AsyncData(null);
  }

  /// Runs [CapabilityProbe] on the connected adapter. Only AT commands plus the
  /// read-only requests 0100/0902 are sent; header/filter state is restored after.
  Future<AdapterCapabilities?> probe() async {
    if (state.isLoading) return state.value;
    final conn = ref.read(connectionProvider);
    if (conn.mode == DataMode.replay) throw const ProbeBlockedException(ProbeBlock.replay);
    final client = conn.client;
    if (client == null || !conn.isConnected) throw const ProbeBlockedException(ProbeBlock.noAdapter);
    if (conn.busy) throw const ProbeBlockedException(ProbeBlock.busy);
    state = const AsyncLoading();
    try {
      final caps = await CapabilityProbe(client.elm).run(info: client.info, transport: client.transport.kind, ecuConnected: conn.ecuReady);
      // The connection may have changed while probing; don't attach stale results.
      if (!ref.mounted || !identical(ref.read(connectionProvider).client, client)) return null;
      state = AsyncData(caps);
      return caps;
    } catch (e, st) {
      if (ref.mounted) state = AsyncError(e, st);
      return null;
    }
  }
}

final adapterCapabilitiesProvider = NotifierProvider<AdapterCapsController, AsyncValue<AdapterCapabilities?>>(AdapterCapsController.new);
