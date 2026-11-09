import 'package:flutter_test/flutter_test.dart';
import 'package:nox_iptv/models/channel.dart';
import 'package:nox_iptv/services/channel_names.dart';

Channel channel(String name) => Channel(
      id: 'p::$name',
      rawId: name,
      playlistId: 'p',
      name: name,
      group: 'Sports',
      url: 'https://example.test/1.ts',
    );

void main() {
  test('a rename replaces the provider name and remembers it', () {
    final c = channel('US: ESPN 2 HD');
    ChannelRenames.applyTo(c, 'ESPN2');
    expect(c.name, 'ESPN2');
    expect(c.originalName, 'US: ESPN 2 HD');
  });

  test('clearing the rename restores the provider name', () {
    final c = channel('US: ESPN 2 HD');
    ChannelRenames.applyTo(c, 'ESPN2');
    ChannelRenames.applyTo(c, null);
    expect(c.name, 'US: ESPN 2 HD');
    expect(c.originalName, isNull);
  });

  test('applying the same rename twice is stable', () {
    final c = channel('Sky Sports 1');
    ChannelRenames.applyTo(c, 'SS1');
    ChannelRenames.applyTo(c, 'SS1');
    expect(c.name, 'SS1');
    expect(c.originalName, 'Sky Sports 1');
  });

  test('a blank name counts as no override', () {
    final c = channel('TSN 1');
    ChannelRenames.applyTo(c, '   ');
    expect(c.name, 'TSN 1');
    expect(c.originalName, isNull);
  });

  test('a rename survives a reloaded channel copy', () {
    final first = channel('US: ESPN 2 HD');
    ChannelRenames.applyTo(first, 'ESPN2');
    final copy = Channel.fromJson(first.toJson());
    expect(copy.originalName, 'US: ESPN 2 HD');
    ChannelRenames.applyTo(copy, null);
    expect(copy.name, 'US: ESPN 2 HD');
  });
}
