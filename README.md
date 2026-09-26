# DNA

A native macOS IRC client built with Swift, AppKit, and Network.framework. DNA includes an amber CRT app icon. No browser, Electron, web server, or third-party runtime. The amber CRT appearance is inspired by [cool-retro-term](https://github.com/Swordfish90/cool-retro-term); its source code is not incorporated.

## Build and launch

Requires macOS 13+ and Xcode command line tools.

```sh
./build.sh
open DNA.app
```

The build script produces a locally signed application bundle. You can drag DNA.app into Applications. This is a local development build, not a notarized distribution.

Press **⌘K** to connect. The connection sheet includes 16 public network presets, 1,402 imported server hostnames, and saved custom servers. The presets are a maintained shortlist, not an exhaustive or live availability guarantee. Network addresses were checked against the [ircbits 2026 overview](https://ircbits.com/articles/irc-networks-overview); broader directories are available at [Netsplit](https://netsplit.de/networks/index.en.php). Defaults: `irc.libera.chat`, TLS port `6697`, channel `#dna`. Enter a nickname before connecting; DNA does not assign one. The last configured nickname is saved locally for the next connection, and server nickname changes update the display. Connection settings are saved locally; chat history is in memory only. DNA starts offline and never connects automatically.

## Commands

- `/join #channel` or `/j #channel` — join a channel
- `/part` or `/p` — leave the current channel
- `/nick name` or `/n name` — change nickname
- `/msg nick message` or `/m nick message` — send a private message
- `/whois nick` or `/w nick` — show user information
- `/me action` — send an action
- `/clear` — clear the current transcript
- `/connect` — open connection settings
- `/quit` or `/q` — disconnect
- `/help` or `/h` — show help

The Display menu provides amber, green, and white phosphor, scanlines, glow, and font sizes from 11 to 21 pt. The selected font size is saved locally. Channels, topics, nicknames, nickname changes, mode changes, quits, and kicks update from server events. TLS validates server certificates using the operating system.

The Nicknames pane shows theme-colored icons for owner (+q), admin (+a), operator (+o), half-operator (+h), voice (+v), normal users, and other network-specific ranks. DNA reads the server’s `PREFIX` advertisement and requests IRCv3 `multi-prefix` for accurate NAMES replies. See the [IRCv3 multi-prefix specification](https://ircv3.net/specs/extensions/multi-prefix) and [channel member prefix definitions](https://defs.ircdocs.horse/defs/chanmembers). AOP and SOP are commonly ChanServ access-list names; the pane shows the related **live** operator and admin modes, which do not prove a user’s ChanServ list membership. Right-click a nickname for WHOIS, CTCP ping, and private chat. When your current channel mode permits it, the menu also offers voice, half-op, operator, admin, and kick actions. The selected member’s rank is checked as well; the server remains the final authority and may reject an action. AOP/SOP access lists are network-specific and are not inferred from channel prefixes.

Current scope: one network at a time, basic IRC commands. SASL authentication, persistent logs, DCC, and automatic reconnection are not implemented.

## Verification

Run `./test.sh` to check IRC parsing and a loopback TCP integration covering registration, PING/PONG, fragmented incoming messages, and outbound messages. The test requires permission to bind a local socket. Public-network TLS connections require separate verification on your network.

## Current features

Channels follow the selected theme. Wrapped chat messages align under their message body. Background conversations pulse when messages arrive, and opening the conversation clears its indicator. Private chats hide the channel topic. The compact header leaves more room for chat; connected status shows the server, port, and elapsed connection time.

Virtualife (`irc.virtualife.org:6697`, TLS, `#informatica`) and VIPChat (`irc.vipchat.com.br:6667`, plain TCP) are included. In Connect, enter server details and choose **Add / Update Server…** to save a named entry locally. The server dropdown bundles concrete hostnames listed across [Netsplit’s worldwide server directory](https://netsplit.de/servers/) domain groups, including entries without detail links. Imported entries use editable TLS/6697 defaults because the listing does not specify ports. Wildcard and malformed hostnames are excluded from the catalog. Availability and TLS support are not guaranteed. Run `python3 Scripts/import-netsplit.py` to refresh the catalog; each group’s parsed count must match the source before the catalog is written. Source counts and retrieval date are saved in `Assets/netsplit-source.json`.

Run `./package-dmg.sh` to build `dist/DNA-1.3.dmg`. Open the disk image and drag DNA into Applications. Quit the previous running DNA before opening the new version. This build is locally signed, not notarized.
