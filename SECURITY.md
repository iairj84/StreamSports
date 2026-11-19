# Security reports

Use **Security → Report a vulnerability** on this repository for a private security report. Please do not post credentials, playlist URLs or unredacted logs in public issues.

For ordinary bugs, include the app version, device model, Android version and steps using sample data. Remove account details, IP addresses, QR codes and identifying information from screenshots and logs before sharing them.

Only the latest release receives fixes. Download APKs from this repository's Releases page; the app includes no playlist, subscription or media service.

## Where your credentials live

StreamSports stores the playlist you add and nothing else. That playlist is the
only secret the app holds: Xtream and Stalker usernames, passwords and portal
identity sit in the app's private preferences, alongside the ordinary settings.

- **They stay on the device.** Android backup is disabled for this app
  (`android:allowBackup="false"`, with `res/xml/backup_rules.xml` and
  `res/xml/data_extraction_rules.xml` excluding the app's data from both cloud
  backup and device-to-device migration). Nothing is copied to Google's backup
  transport or to a new device behind your back.
- **Moving a configuration is your decision.** *Settings → Backups & transfer*
  encrypts a configuration before it leaves the device, and the receiving
device must accept it. A local backup file is kept in the app's private
  documents folder and is **not** encrypted, because it never leaves that folder
  and encrypting it would make it useless for the disaster-recovery case it
  exists for.
- **Errors are scrubbed.** A failed provider request can quote the full URL,
  including `username=` and `password=`. Settings, the home screen and the
  playback error panel show the host only; message text never includes the
  credentials.
- **Logs.** Logcat receives exception *types* for provider failures, not
  addresses. If you share a log, it still may contain provider hostnames you
  consider private.
