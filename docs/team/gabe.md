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

**Watch for later:** ping goes 25 ms to 107 ms while the line is uploading. That is bufferbloat, and
the server uploads constantly to every player. If matches feel laggy at 8+ players, this is the first
suspect, and the fix is a router queue setting, not game code (see T06).

**Wired, not wireless:** this PC is on Wi-Fi today. Plug the server into Ethernet before the playtest.
That changes its local address, so the port forward must be redone for the Ethernet adapter.
