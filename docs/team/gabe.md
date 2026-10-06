# Gabe

Fill this in during T01-T03. Never write your public IP address here (this repo is public).

| Field | Answer |
| --- | --- |
| Role | Tech lead, Heroes & Combat |
| GitHub username | gabrielsfprofessional |
| Real hours per week | 5 |
| Best weekly sync time | Thursday 5:00 pm |
| PC: Windows version | Windows 11 Home, build 26300 |
| PC: CPU | Intel Core i7-10750H @ 2.60 GHz (6 cores) |
| PC: graphics | NVIDIA GeForce RTX 2060 (Intel UHD integrated as well) |
| PC: RAM | 16 GB |
| PC: screen resolution | 1920x1080 |
| Internet type (cable, fiber, other) | Cable (Xfinity) |
| Upload speed (Mbps) | 31.23 |
| Behind CGNAT? (yes/no) | no |
| UDP 7777 forwarded to this PC? (yes/no) | yes |
| Firewall rule added? (yes/no) | yes |

## T03 network check

Measured Tue Oct 6 2026, 6:50 pm, over Wi-Fi.

| Reading | Value |
| --- | --- |
| Download | 865 Mbps |
| Upload | 31.23 Mbps (one run) |
| Ping, idle | 25 ms |
| Ping, while uploading | 107 ms |

- Upload clears the 10 Mbps bar with room to spare.
- Port forward was made in the Xfinity app, UDP 7777 to this PC's reserved address.
- Windows firewall: inbound allow rule on UDP 7777, Wi-Fi profile set to Private.

**Still pending:** reachable from another house. Gabe and John test it the evening of Tue Oct 6 2026;
the real proof arrives with T06, when there is a server to connect to.

**Watch for later:** Ping rises from 25 ms to 107 ms only when the upload is maxed out, which the
speed test does on purpose. The game server needs about 1-3 Mbps of the 31, so on its own it stays
near 25 ms. The risk is something else maxing the upload during a match: OneDrive, phone photo
backups, video calls. Pause them while hosting. The Xfinity gateway has no queue setting to fix this.

**Wired, not wireless:** this PC is on Wi-Fi today. Plug the server into Ethernet before the playtest.
That changes its local address, so the port forward must be redone for the Ethernet adapter, and set
the Ethernet network to Private so the firewall rule applies.
