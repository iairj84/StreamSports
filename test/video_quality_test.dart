import 'package:flutter_test/flutter_test.dart';
import 'package:nox_iptv/utils/video_quality.dart';

void main() {
  test('decoded-track labels cover 4K down to SD', () {
    expect(qualityLabelForTrack(height: 2160), '4K');
    expect(qualityLabelForTrack(height: 3840), '4K');
    expect(qualityLabelForTrack(height: 1080), 'HD');
    expect(qualityLabelForTrack(height: 1080, frameRate: 60), 'FHD');
    expect(qualityLabelForTrack(height: 1080, frameRate: 30), 'HD');
    expect(qualityLabelForTrack(height: 1440), 'HD');
    expect(qualityLabelForTrack(height: 720), 'HD');
    expect(qualityLabelForTrack(height: 719), 'SD');
    expect(qualityLabelForTrack(height: 480), 'SD');
    expect(qualityLabelForTrack(height: 479), isNull);
    expect(qualityLabelForTrack(height: 0), isNull);
  });
}
