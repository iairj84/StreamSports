# Install StreamSports

**[Download app-release.apk](https://github.com/iairj84/StreamSports/releases)** — open the newest release and pick `app-release.apk` under Assets.

The same APK supports 32-bit and 64-bit ARM phones, Android TV and Google TV on Android 7.0 or newer. It does not support Samsung Tizen, LG webOS, iOS or x86 Android devices. The app includes no channels or subscriptions.

## Android phone or tablet

1. Open the releases page above in your browser and download `app-release.apk`.
2. Open the downloaded file.
3. If prompted, allow that browser or file manager to **install unknown apps**, then return to the installer and choose **Install**. Menu names vary by device. You can turn that permission off afterwards.
4. Open StreamSports and add your playlist under **Settings → Playlists & guide → Add Playlist**.

## Android TV or Google TV

1. Install [Downloader by AFTVnews](https://play.google.com/store/apps/details?id=com.esaba.downloader) from the TV's Play Store.
2. In Downloader, enter the release page address `github.com/iairj84/StreamSports/releases` and choose **Go**, then download `app-release.apk` from the newest release.
3. Allow Downloader to **install unknown apps** when prompted, then install the APK. On some TVs this permission is under **Settings → Apps → Special app access** or **Security & restrictions**.
4. Open StreamSports from the TV's apps list and add your playlist.

Alternatively, download the APK on your phone and transfer it to the TV, then open it with the TV's file manager. Developer mode and wireless debugging are not needed for these installation methods.

## Copying a setup to another device

Both devices need the same app version on the same Wi-Fi:

1. On the new device: **Settings → Devices & app → Transfer to another device → Receive on this device**.
2. On the existing device: the same screen, then **Send from this device**, and pick the other device from the list.
3. Both screens show a six-digit code. If the codes match, accept on the receiving device and send from the other one.

The receiving device is **replaced**, not merged: its playlists, settings, sports picks, favorites and channel links are overwritten with the sender's copy. Anything that existed only on the receiving device is lost.

## Updates and troubleshooting

- Download the latest APK and install it over the existing app. Releases retain the application ID and signing certificate, so Android can update the app while keeping its data. Do not uninstall first.
- Updates are manual from the releases page, or through **Settings → Devices & app → App updates**, which checks hourly and can skip a version.
- If Android refuses an update, check that the APK came from this repository and that enough storage is available. An installation signed by someone else cannot be updated with this APK.
- If a device's security policy blocks installation, follow its supported installation process. Do not disable Play Protect to force installation.

[Latest release](https://github.com/iairj84/StreamSports/releases) · [Set up playlists](../README.md#get-started)
