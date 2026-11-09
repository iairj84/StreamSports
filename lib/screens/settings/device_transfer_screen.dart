import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/l10n.dart';
import '../../services/device_transfer_service.dart';
import '../../services/playlist_manager.dart';
import '../../services/settings_bundle.dart';
import '../../services/storage_service.dart';
import '../../widgets/settings_scaffold.dart';
import '../../widgets/settings_section.dart';

/// Copies this device's playlists, settings, sports picks and lists to another
/// device on the same Wi-Fi. The receiving device is replaced, never merged —
/// the warning says so before anything is accepted.
class DeviceTransferScreen extends StatefulWidget {
  const DeviceTransferScreen({super.key});

  @override
  State<DeviceTransferScreen> createState() => _DeviceTransferScreenState();
}

enum _Role { choose, send, receive }

class _DeviceTransferScreenState extends State<DeviceTransferScreen> {
  _Role _role = _Role.choose;
  TransferReceiver? _receiver;
  StreamSubscription<ReceiverStatus>? _statusSub;
  ReceiverStatus _status = const ReceiverStatus(phase: TransferPhase.idle);
  TransferSender? _sender;
  StreamSubscription<List<TransferPeer>>? _peerSub;
  List<TransferPeer> _peers = const [];
  TransferPeer? _peer;
  SenderHandshake? _handshake;
  bool _busy = false;
  bool _reloading = false;
  bool _reloaded = false;
  String? _error;
  String? _result;

  StorageService get _storage => context.read<StorageService>();

  @override
  void dispose() {
    _statusSub?.cancel();
    _peerSub?.cancel();
    _receiver?.dispose();
    _sender?.dispose();
    super.dispose();
  }

  Future<void> _startReceiver() async {
    setState(() {
      _role = _Role.receive;
      _busy = true;
      _reloaded = false;
      _reloading = false;
      _error = null;
      _result = null;
    });
    final receiver = _receiver = TransferReceiver(_storage,
        deviceName: 'This device');
    _statusSub = receiver.status.listen((status) {
      if (mounted) setState(() => _status = status);
      if (status.phase == TransferPhase.done && !_reloaded) {
        _reloaded = true;
        _reloadPlaylists();
      }
    });
    try {
      await receiver.start();
    } catch (e) {
      setState(() => _error =
          'Could not open the transfer on this network. Check that both devices are on the same Wi-Fi.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _startSender() async {
    setState(() {
      _role = _Role.send;
      _busy = true;
      _error = null;
      _result = null;
      _peers = const [];
    });
    final sender = _sender = TransferSender(_storage, deviceName: 'This device');
    _peerSub = sender.devices.listen((peers) {
      if (mounted) setState(() => _peers = peers);
    });
    try {
      await sender.discover();
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Could not search this network for devices.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _connect(TransferPeer peer) async {
    setState(() {
      _busy = true;
      _peer = peer;
      _error = null;
      _result = null;
      _handshake = null;
    });
    try {
      final handshake = await _sender!.request(peer);
      if (!mounted) return;
      if (!handshake.approved) {
        setState(() {
          _handshake = null;
          _peer = null;
          _error = handshake.code.isEmpty
              ? 'The other device declined the transfer.'
              : 'The two codes did not match, so nothing was sent.';
        });
        return;
      }
      setState(() => _handshake = handshake);
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'The other device did not answer. Try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendAll() async {
    final peer = _peer;
    final handshake = _handshake;
    if (peer == null || handshake == null) return;
    setState(() {
      _busy = true;
      _error = null;
      _result = null;
    });
    try {
      final report = await _sender!.send(peer, handshake,
          sections: TransferSection.values.toSet());
      if (!mounted) return;
      setState(() {
        _handshake = null;
        _result =
            'Copied ${report?.values ?? 0} settings to ${peer.name}. Its playlists, settings and sports picks now match this device.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e is StateError
          ? e.message
          : 'The transfer did not finish: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// A transfer replaces the playlists in storage; load them in place so the
  /// guide and the tabs show the new ones without closing the app.
  Future<void> _reloadPlaylists() async {
    setState(() => _reloading = true);
    try {
      await context.read<PlaylistManager>().reloadFromStorage();
    } catch (_) {
      // The settings are saved either way; the next launch loads them too.
    } finally {
      if (mounted) setState(() => _reloading = false);
    }
  }

  /// Show progress the moment the button is tapped; the sender can take a
  /// few seconds to encrypt and upload a large playlist bundle.
  Future<void> _approve() async {
    setState(() => _status = ReceiverStatus(
        phase: TransferPhase.receiving, address: _status.address));
    await _receiver?.approve();
  }

  Future<void> _reset() async {
    _statusSub?.cancel();
    await _receiver?.stop();
    _receiver = null;
    _sender?.dispose();
    _sender = null;
    _peerSub?.cancel();
    if (!mounted) return;
    setState(() {
      _role = _Role.choose;
      _status = const ReceiverStatus(phase: TransferPhase.idle);
      _peers = const [];
      _peer = null;
      _handshake = null;
      _reloaded = false;
      _reloading = false;
      _error = null;
      _result = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SettingsScaffold(
      title: tr('Transfer to another device'),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        // Results and failures go first: below the fold they read as nothing
        // happening, which is exactly how the first broken transfer looked.
        if (_result != null) _ResultCard(message: _result!, onDone: _reset),
        if (_error != null) _ErrorCard(message: _error!),
        if (_role == _Role.choose) ...[
          SettingsSection(title: tr('Copy this device to another'), children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                  tr('Both devices need to be on the same Wi-Fi. Nothing goes through a server, and the data is encrypted on the way.'),
                  style: Theme.of(context).textTheme.bodyMedium),
            ),
            _RoleButton(
              icon: Icons.upload,
              title: tr('Send from this device'),
              subtitle: tr('Make the other device match this one'),
              onTap: _startSender,
            ),
            _RoleButton(
              icon: Icons.download,
              title: tr('Receive on this device'),
              subtitle: tr('Replace this device with the other one'),
              onTap: _startReceiver,
            ),
          ]),
          _ReplaceWarning(),
        ],
        if (_role == _Role.send) ..._sendBody(context),
        if (_role == _Role.receive) ..._receiveBody(context),
      ]),
    );
  }

  List<Widget> _sendBody(BuildContext context) {
    final handshake = _handshake;
    final peer = _peer;
    if (_result != null) return const [];
    return [
      SettingsSection(title: tr('Send from this device'), children: [
        if (handshake != null && peer != null) ...[
          _CodeCard(code: handshake.code, peer: peer.name),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
                tr('Check that the other device shows the same code, then send. Its playlists, settings and sports picks will be replaced.'),
                style: Theme.of(context).textTheme.bodyMedium),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(children: [
              TextButton(onPressed: _reset, child: Text(tr('Cancel'))),
              const SizedBox(width: 12),
              FilledButton(
                  onPressed: _busy ? null : _sendAll,
                  child: Text(tr('Send settings'))),
            ]),
          ),
        ] else ...[
          if (_busy)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_peers.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                  tr('No devices found. Start “Receive on this device” on the other device, then search again.'),
                  style: Theme.of(context).textTheme.bodyMedium),
            ),
          for (final peer in _peers)
            ListTile(
              leading: const Icon(Icons.tv),
              title: Text(peer.name),
              subtitle: Text(peer.address),
              enabled: !_busy,
              onTap: () => _connect(peer),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(children: [
              TextButton(onPressed: _busy ? null : _startSender, child: Text(tr('Search again'))),
              const Spacer(),
              TextButton(onPressed: _reset, child: Text(tr('Cancel'))),
            ]),
          ),
        ],
      ]),
    ];
  }

  List<Widget> _receiveBody(BuildContext context) {
    final status = _status;
    return [
      SettingsSection(title: tr('Receive on this device'), children: [
        if (status.phase == TransferPhase.done)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr('Transfer complete'), style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(
                  tr(_reloading
                      ? '${status.report?.values ?? 0} settings were copied. Reloading this device’s playlists…'
                      : '${status.report?.values ?? 0} settings were copied, and this device’s playlists were reloaded.'),
                  style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 16),
              FilledButton(onPressed: _reset, child: Text(tr('Done'))),
            ]),
          )
        else if (status.phase == TransferPhase.approval)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _CodeCard(code: status.code ?? '------', peer: status.peerName ?? 'the other device'),
              const SizedBox(height: 12),
              Text(tr('If that code matches the other device, accept. This device’s playlists, settings and sports picks will be replaced with a copy from it.'),
                  style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 16),
              Row(children: [
                TextButton(onPressed: _receiver?.reject, child: Text(tr('Decline'))),
                const SizedBox(width: 12),
                FilledButton(onPressed: _approve, child: Text(tr('Accept and replace'))),
              ]),
            ]),
          )
        else if (status.phase == TransferPhase.receiving)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(tr('Receiving the settings…'),
                  style: Theme.of(context).textTheme.bodyMedium),
            ]),
          )
        else if (status.phase == TransferPhase.failed)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(status.message ?? tr('The transfer failed.'),
                  style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 12),
              TextButton(onPressed: _startReceiver, child: Text(tr('Try again'))),
            ]),
          )
        else ...[
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (_busy)
                const Center(child: CircularProgressIndicator())
              else
                Text(tr('Waiting for the other device. On it, choose “Send from this device” and pick this one.'),
                    style: Theme.of(context).textTheme.bodyMedium),
              if (status.address != null) ...[
                const SizedBox(height: 8),
                Text(tr('This device: ${status.address}'),
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextButton(onPressed: _reset, child: Text(tr('Stop'))),
          ),
        ],
      ]),
      _ReplaceWarning(),
    ];
  }
}

class _RoleButton extends StatelessWidget {
  const _RoleButton(
      {required this.icon,
      required this.title,
      required this.subtitle,
      required this.onTap});
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      );
}

class _CodeCard extends StatelessWidget {
  const _CodeCard({required this.code, required this.peer});
  final String code;
  final String peer;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12)),
        child: Column(children: [
          Text(tr('Code for $peer'),
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          Text(code,
              style: Theme.of(context)
                  .textTheme
                  .displayMedium
                  ?.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
        ]),
      );
}

class _ReplaceWarning extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(top: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.errorContainer,
            borderRadius: BorderRadius.circular(12)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.warning_amber_rounded,
              color: Theme.of(context).colorScheme.onErrorContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
                tr('A transfer replaces the receiving device’s playlists, settings, sports picks, favorites and channel links. Anything only on that device is lost.'),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onErrorContainer)),
          ),
        ]),
      );
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.message, required this.onDone});
  final String message;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.check_circle_outline,
                color: Theme.of(context).colorScheme.onPrimaryContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Text(message,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onPrimaryContainer)),
            ),
          ]),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(onPressed: onDone, child: Text(tr('Done'))),
          ),
        ]),
      );
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(top: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.errorContainer,
            borderRadius: BorderRadius.circular(12)),
        child: Text(message,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onErrorContainer)),
      );
}
