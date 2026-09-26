import AppKit
import Network

let amber = NSColor(calibratedRed: 0.94, green: 0.68, blue: 0.35, alpha: 1)
let dark = NSColor(calibratedRed: 0.065, green: 0.075, blue: 0.06, alpha: 1)
struct IRCNetwork: Codable {
    let name: String
    let host: String
    var port: Int = 6697
    var tls: Bool = true
    var channel: String = "#dna"
}
struct ChatEntry {
    let time: String
    let sender: String
    let message: String
}
let publicNetworks: [IRCNetwork] = [
    .init(name: "Libera.Chat", host: "irc.libera.chat"),
    .init(name: "OFTC", host: "irc.oftc.net"),
    .init(name: "Undernet", host: "irc.undernet.org"),
    .init(name: "IRCnet", host: "open.ircnet.net"),
    .init(name: "hackint", host: "irc.hackint.org"),
    .init(name: "Rizon", host: "irc.rizon.net"),
    .init(name: "EFnet", host: "irc.efnet.org"),
    .init(name: "DALnet", host: "irc.dal.net"),
    .init(name: "freenode", host: "irc.freenode.net"),
    .init(name: "QuakeNet", host: "irc.quakenet.org"),
    .init(name: "GameSurge", host: "irc.gamesurge.net"),
    .init(name: "EsperNet", host: "irc.esper.net"),
    .init(name: "Snoonet", host: "irc.snoonet.org"),
    .init(name: "tilde.chat", host: "irc.tilde.chat"),
    .init(name: "Virtualife", host: "irc.virtualife.org", channel: "#informatica"),
    .init(name: "VIPChat", host: "irc.vipchat.com.br", port: 6667, tls: false, channel: "")
]
func loadServerCatalog(from url: URL?) -> [IRCNetwork] {
    guard let url, let data = try? Data(contentsOf: url),
          let servers = try? JSONDecoder().decode([IRCNetwork].self, from: data) else { return [] }
    return servers
}
let directoryServers = loadServerCatalog(from: Bundle.main.url(forResource: "netsplit-servers", withExtension: "json"))
func mergedServers(_ catalog: [IRCNetwork], saved: [IRCNetwork]) -> [IRCNetwork] {
    var seen = Set<String>()
    // Configured presets retain their ports and startup channels.
    return (publicNetworks + saved + catalog).filter { seen.insert($0.host.lowercased() + ":" + String($0.port)).inserted }.map { entry in
        saved.last { $0.host.caseInsensitiveCompare(entry.host) == .orderedSame && $0.port == entry.port } ?? entry
    }
}
func mono(_ size: CGFloat) -> NSFont { NSFont.monospacedSystemFont(ofSize: size, weight: .regular) }
func label(_ value: String, size: CGFloat = 12) -> NSTextField {
    let v = NSTextField(labelWithString: value); v.font = mono(size); v.textColor = amber; return v
}
struct IRCMessage {
    var prefix = "", command = "", params: [String] = []
    init(_ line: String) {
        var text = line
        if text.hasPrefix("@"), let space = text.firstIndex(of: " ") { text = String(text[text.index(after: space)...]) }
        if text.hasPrefix(":"), let space = text.firstIndex(of: " ") { prefix = String(text[text.index(after: text.startIndex)..<space]); text = String(text[text.index(after: space)...]) }
        if let range = text.range(of: " :") { params = text[..<range.lowerBound].split(separator: " ").map(String.init); params.append(String(text[range.upperBound...])) }
        else { params = text.split(separator: " ").map(String.init) }
        if !params.isEmpty { command = params.removeFirst().uppercased() }
    }
    var nick: String { String(prefix.split(separator: "!").first ?? "server") }
}
class IRCClient {
    var connection: NWConnection?
    var onLine: ((String) -> Void)?
    var onState: ((String) -> Void)?
    private var pending = Data()
    func connect(host: String, port: UInt16, nick: String, encrypted: Bool) {
        disconnect(); pending = Data()
        let c = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!, using: encrypted ? .tls : .tcp)
        connection = c
        c.stateUpdateHandler = { [weak self, weak c] state in
            guard let self, let c, self.connection === c else { return }
            switch state {
            case .ready: self.onState?("REGISTERING"); self.send("CAP REQ :multi-prefix"); self.send("NICK \(nick)"); self.send("USER dna 0 * :DNA IRC client"); self.send("CAP END"); self.receive(c)
            case .failed(let error): self.onState?("ERROR: \(error.localizedDescription)"); c.cancel()
            case .waiting(let error): self.onState?("WAITING: \(error.localizedDescription)")
            case .cancelled: self.onState?("DISCONNECTED")
            default: break
            }
        }
        onState?("CONNECTING"); c.start(queue: .main)
    }
    func receive(_ c: NWConnection) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self, weak c] data, _, complete, error in
            guard let self, let c, self.connection === c else { return }
            if let data {
                self.pending.append(data)
                while let end = self.pending.firstIndex(of: 10) {
                    let line = String(decoding: self.pending[..<end], as: UTF8.self).trimmingCharacters(in: .newlines)
                    self.pending.removeSubrange(...end)
                    if line.hasPrefix("PING ") { self.send("PONG \(line.dropFirst(5))") }
                    else { self.onLine?(line) }
                }
                if self.pending.count > 65536 { self.onState?("ERROR: oversized server response"); self.disconnect(); return }
            }
            if complete || error != nil { self.onState?("DISCONNECTED"); c.cancel() }
            else { self.receive(c) }
        }
    }
    func send(_ line: String) {
        guard !line.contains("\r"), !line.contains("\n"), !line.contains("\0"), line.utf8.count <= 510 else { onState?("ERROR: invalid or oversized message"); return }
        connection?.send(content: Data((line + "\r\n").utf8), completion: .contentProcessed { [weak self] error in if let error { self?.onState?("ERROR: \(error.localizedDescription)") } })
    }
    func disconnect() { connection?.cancel(); connection = nil }
}
struct ChannelPrefixes {
    var modes = Array("qaohv")
    var symbols = Array("~&@%+")
    mutating func update(_ token: String) {
        guard token.hasPrefix("PREFIX=("), let end = token.firstIndex(of: ")") else { return }
        let start = token.index(token.startIndex, offsetBy: 8)
        let newModes = Array(token[start..<end])
        let newSymbols = Array(token[token.index(after: end)...])
        guard !newModes.isEmpty, newModes.count == newSymbols.count else { return }
        modes = newModes; symbols = newSymbols
    }
    func parseName(_ entry: String) -> (nick: String, modes: Set<Character>) {
        var rest = entry[...], found = Set<Character>()
        while let symbol = rest.first, let index = symbols.firstIndex(of: symbol) {
            found.insert(modes[index]); rest.removeFirst()
        }
        return (String(rest.split(separator: "!").first ?? ""), found)
    }
    func icon(for active: Set<Character>) -> String {
        for mode in modes where active.contains(mode) {
            switch mode {
            case "q": return "★" // founder / owner
            case "a": return "◆" // admin; often SOP-style privileges
            case "o": return "●" // channel operator; often AOP-style privileges
            case "h": return "◐" // half-operator
            case "v": return "✦" // voiced
            default: return "◇" // network-specific rank
            }
        }
        return "○" // normal member
    }
    func order(for active: Set<Character>) -> Int { modes.firstIndex(where: { active.contains($0) }) ?? modes.count }
}
struct ChannelPermissions {
    let own: Set<Character>, target: Set<Character>, prefixes: ChannelPrefixes
    var canModerate: Bool {
        !own.intersection(Set("qaoh")).isEmpty && prefixes.order(for: own) < prefixes.order(for: target)
    }
    var canVoice: Bool { canModerate && prefixes.modes.contains("v") }
    var canHalfOp: Bool { canModerate && !own.intersection(Set("qao")).isEmpty && prefixes.modes.contains("h") }
    var canOp: Bool { canModerate && !own.intersection(Set("qao")).isEmpty && prefixes.modes.contains("o") }
    var canAdmin: Bool { canModerate && own.contains("q") && prefixes.modes.contains("a") }
}
func expandedSlashCommand(_ command: String) -> String {
    switch command.lowercased() {
    case "j": return "join"
    case "p": return "part"
    case "n": return "nick"
    case "m": return "msg"
    case "w": return "whois"
    case "q": return "quit"
    case "h": return "help"
    default: return command.lowercased()
    }
}
class CRTView: NSView {
    var enabled = true { didSet { needsDisplay = true } }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) {
        guard enabled else { return }
        NSColor.black.withAlphaComponent(0.13).setFill()
        for y in stride(from: CGFloat(0), to: bounds.height, by: 3) { NSRect(x: 0, y: y, width: bounds.width, height: 1).fill() }
    }
}
class NicknameTableView: NSTableView {
    var menuForRow: ((Int) -> NSMenu?)?
    override func menu(for event: NSEvent) -> NSMenu? {
        let index = row(at: convert(event.locationInWindow, from: nil))
        guard index >= 0 else { return nil }
        selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        return menuForRow?(index)
    }
}
enum NicknameCommand: Int {
    case whois = 1, ping, privateChat, giveVoice, removeVoice, giveHalfOp, removeHalfOp, giveOp, removeOp, giveAdmin, removeAdmin, kick
}
class App: NSObject, NSApplicationDelegate, NSWindowDelegate, NSTextFieldDelegate, NSTableViewDataSource, NSTableViewDelegate {
    var window: NSWindow!
    let client = IRCClient(), transcript = NSTextView(), input = NSTextField(), table = NSTableView(), members = NicknameTableView()
    let status = label("○ OFFLINE", size: 10), title = label("# DNA", size: 20), topic = label("A little old school. A lot more human.", size: 11), crt = CRTView(), identity = label("", size: 12), memberLegend = label("★ OWNER\n◆ ADMIN / SOP-LIKE\n● OP / AOP-LIKE\n◐ HALFOP\n✦ VOICE\n○ NORMAL\n◇ OTHER", size: 9)
    var channels = ["server"], current = "server", nick = "", initialChannel = "#dna", registered = false
    var lastUsedNick = UserDefaults.standard.string(forKey: "lastConfiguredNick") ?? ""
    var histories: [String: [ChatEntry]] = [:], names: [String: Set<String>] = [:], memberModes: [String: [String: Set<Character>]] = [:], topics: [String: String] = [:]
    var visibleNicknames: [String] = []
    var savedServers: [IRCNetwork] = (UserDefaults.standard.data(forKey: "savedServers").flatMap { try? JSONDecoder().decode([IRCNetwork].self, from: $0) }) ?? []
    var availableServers: [IRCNetwork] { mergedServers(directoryServers, saved: savedServers) }
    var unread = Set<String>(), blinkOn = true
    var connectedAt: Date?, connectionHost = "", connectionPort = 0
    var refreshTimer: Timer?
    var pingRequests: [String: (nick: String, started: Date, channel: String)] = [:]
    var whoisDestinations: [String: String] = [:]
    var prefixes = ChannelPrefixes(), channelModeGroups = [Set("bIe"), Set("k"), Set("l"), Set<Character>()]
    var color = amber, glow: CGFloat = 3
    var framedPanels: [NSView] = []
    var fontSize = 13
    var fontSizeItems: [NSMenuItem] = []
    var connectPanel: NSPanel?, hostField = NSTextField(), portField = NSTextField(), nickField = NSTextField(), channelField = NSTextField(), tlsCheck = NSButton(checkboxWithTitle: "Use TLS encryption", target: nil, action: nil), networkPicker = NSPopUpButton()
    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu(); buildWindow()
        client.onLine = { [weak self] in self?.handle($0) }
        client.onState = { [weak self] state in guard let self else { return }; self.status.stringValue = "○ \(state)"; self.append("—", state, channel: "server"); if state == "DISCONNECTED" || state.hasPrefix("ERROR") { self.registered = false; self.connectedAt = nil } }
        append("DNA", "Welcome to DNA.", channel: "server")
        window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 0.75, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.blinkOn.toggle()
            if !self.unread.isEmpty { self.table.reloadData() }
            self.updateConnectionStatus()
        }
    }
    func buildMenu() {
        let menu = NSMenu(), appItem = NSMenuItem(); menu.addItem(appItem); let appMenu = NSMenu(); appItem.submenu = appMenu
        appMenu.addItem(withTitle: "About DNA", action: #selector(about), keyEquivalent: "").target = self
        appMenu.addItem(.separator()); appMenu.addItem(withTitle: "Quit DNA", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let connectionItem = NSMenuItem(); menu.addItem(connectionItem); let cm = NSMenu(title: "Connection"); connectionItem.submenu = cm
        cm.addItem(withTitle: "Connect…", action: #selector(showConnect), keyEquivalent: "k").target = self
        cm.addItem(withTitle: "Disconnect", action: #selector(disconnect), keyEquivalent: "d").target = self
        let editItem = NSMenuItem(); menu.addItem(editItem); let edit = NSMenu(title: "Edit"); editItem.submenu = edit
        for (name, selector, key) in [("Undo", "undo:", "z"), ("Cut", "cut:", "x"), ("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] { edit.addItem(withTitle: name, action: Selector(selector), keyEquivalent: key) }
        let displayItem = NSMenuItem(); menu.addItem(displayItem); let dm = NSMenu(title: "Display"); displayItem.submenu = dm
        for (name, tag) in [("Amber phosphor", 0), ("Green phosphor", 1), ("Paper white", 2)] { let item = dm.addItem(withTitle: name, action: #selector(theme(_:)), keyEquivalent: ""); item.tag = tag; item.target = self }
        dm.addItem(withTitle: "Toggle scanlines", action: #selector(toggleScan), keyEquivalent: "s").target = self
        dm.addItem(withTitle: "Toggle glow", action: #selector(toggleGlow), keyEquivalent: "g").target = self
        dm.addItem(.separator())
        let sizeItem = NSMenuItem(title: "Font Size", action: nil, keyEquivalent: "")
        let sizeMenu = NSMenu(title: "Font Size")
        for size in [11, 13, 15, 17, 19, 21] {
            let item = sizeMenu.addItem(withTitle: "\(size) pt", action: #selector(changeFontSize(_:)), keyEquivalent: "")
            item.tag = size; item.target = self; fontSizeItems.append(item)
        }
        sizeItem.submenu = sizeMenu; dm.addItem(sizeItem)
        NSApp.mainMenu = menu
    }
    func buildWindow() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1160, height: 760), styleMask: [.titled,.closable,.miniaturizable,.resizable], backing: .buffered, defer: false)
        window.title = "DNA — Internet Relay Chat"; window.minSize = NSSize(width: 760, height: 480); window.center(); window.backgroundColor = dark
        window.delegate = self
        let root = window.contentView!; root.wantsLayer = true; root.layer?.backgroundColor = dark.cgColor
        let brand = label("DNA", size: 24), tagline = label("INTERNET RELAY CHAT", size: 10)
        let connect = NSButton(title: "CONNECT ↗", target: self, action: #selector(showConnect)); connect.bezelStyle = .rounded
        let header = NSStackView(views: [brand,tagline,NSView(),connect]); header.orientation = .horizontal; header.spacing = 22
        let channelLabel = label("CHANNELS", size: 10)
        table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("channel"))); table.headerView = nil; table.backgroundColor = dark; table.rowHeight = 36; table.delegate = self; table.dataSource = self; table.selectionHighlightStyle = .regular
        let channelScroll = NSScrollView(); channelScroll.documentView = table; channelScroll.hasVerticalScroller = true; channelScroll.drawsBackground = false
        identity.isHidden = true
        let left = NSStackView(views: [channelLabel,channelScroll,identity]); left.orientation = .vertical; left.alignment = .leading; left.spacing = 18
        let messageScroll = NSScrollView(); messageScroll.documentView = transcript; messageScroll.hasVerticalScroller = true; messageScroll.drawsBackground = false
        transcript.isEditable = false; transcript.isSelectable = true; transcript.backgroundColor = dark; transcript.textContainerInset = NSSize(width: 16, height: 22); transcript.autoresizingMask = [.width]; transcript.isVerticallyResizable = true; transcript.isHorizontallyResizable = false; transcript.textContainer?.widthTracksTextView = true
        input.font = mono(13); input.textColor = color; input.backgroundColor = dark; input.isBordered = false; input.focusRingType = .none; input.target = self; input.action = #selector(submit); input.delegate = self
        let composer = NSStackView(views: [label("❯", size: 20),input]); composer.orientation = .horizontal; composer.spacing = 14
        let center = NSStackView(views: [title,topic,messageScroll,composer,label("↵ SEND     /help COMMANDS", size: 9)]); center.orientation = .vertical; center.alignment = .leading; center.spacing = 14
        let nicknameColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("nickname"))
        nicknameColumn.width = 150
        members.addTableColumn(nicknameColumn)
        members.headerView = nil; members.backgroundColor = dark; members.rowHeight = 28
        members.selectionHighlightStyle = .regular; members.delegate = self; members.dataSource = self
        members.menuForRow = { [weak self] row in self?.nicknameMenu(for: row) }
        let memberScroll = NSScrollView(); memberScroll.documentView = members; memberScroll.hasVerticalScroller = true; memberScroll.drawsBackground = false
        let right = NSStackView(views: [label("NICKNAMES", size: 10),memberScroll,memberLegend]); right.orientation = .vertical; right.alignment = .leading; right.spacing = 14
        left.edgeInsets = NSEdgeInsets(top: 16, left: 14, bottom: 16, right: 14)
        center.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        right.edgeInsets = NSEdgeInsets(top: 16, left: 14, bottom: 16, right: 14)
        framedPanels = [left, center, right]
        for panel in framedPanels { panel.wantsLayer = true; panel.layer?.cornerRadius = 8; panel.layer?.borderWidth = 1 }
        let content = NSStackView(views: [left,center,right]); content.orientation = .horizontal; content.alignment = .top; content.spacing = 14
        let footer = NSStackView(views: [status]); footer.orientation = .horizontal
        for view in [header,content,footer,crt] { view.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(view) }
        for view in [left,center,right,channelScroll,messageScroll,memberScroll,composer,input] { view.translatesAutoresizingMaskIntoConstraints = false }
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: root.topAnchor,constant: 12),header.leadingAnchor.constraint(equalTo: root.leadingAnchor,constant: 28),header.trailingAnchor.constraint(equalTo: root.trailingAnchor,constant: -28),header.heightAnchor.constraint(equalToConstant: 32),
            content.topAnchor.constraint(equalTo: header.bottomAnchor,constant: 12),content.leadingAnchor.constraint(equalTo: header.leadingAnchor),content.trailingAnchor.constraint(equalTo: header.trailingAnchor),content.bottomAnchor.constraint(equalTo: footer.topAnchor,constant: -25),
            footer.leadingAnchor.constraint(equalTo: header.leadingAnchor),footer.trailingAnchor.constraint(equalTo: header.trailingAnchor),footer.bottomAnchor.constraint(equalTo: root.bottomAnchor,constant: -20),
            center.widthAnchor.constraint(equalTo: content.widthAnchor,constant: -378),left.widthAnchor.constraint(equalToConstant: 170),right.widthAnchor.constraint(equalToConstant: 180),left.heightAnchor.constraint(equalTo: content.heightAnchor),center.heightAnchor.constraint(equalTo: content.heightAnchor),right.heightAnchor.constraint(equalTo: content.heightAnchor),
            channelScroll.widthAnchor.constraint(equalTo: left.widthAnchor,constant: -28),messageScroll.widthAnchor.constraint(equalTo: center.widthAnchor,constant: -32),memberScroll.widthAnchor.constraint(equalTo: right.widthAnchor,constant: -28),composer.widthAnchor.constraint(equalTo: center.widthAnchor,constant: -32),
            crt.leadingAnchor.constraint(equalTo: root.leadingAnchor),crt.trailingAnchor.constraint(equalTo: root.trailingAnchor),crt.topAnchor.constraint(equalTo: header.bottomAnchor,constant: 10),crt.bottomAnchor.constraint(equalTo: footer.topAnchor,constant: -10)
        ])
        table.selectRowIndexes(IndexSet(integer: 0),byExtendingSelection: false)
        crt.enabled = !UserDefaults.standard.bool(forKey: "noScan")
        applyTheme(UserDefaults.standard.integer(forKey: "theme"))
        let savedSize = UserDefaults.standard.integer(forKey: "fontSize")
        applyFontSize([11, 13, 15, 17, 19, 21].contains(savedSize) ? savedSize : 13)
        window.makeFirstResponder(input)
    }
    func numberOfRows(in tableView: NSTableView) -> Int { tableView === members ? visibleNicknames.count : channels.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard tableView === members else {
            let channel = channels[row]
            let value = label((unread.contains(channel) ? "● " : "") + (channel == "server" ? "⌁  server" : channel), size: CGFloat(fontSize - 1))
            value.textColor = color.withAlphaComponent(unread.contains(channel) && !blinkOn ? 0.4 : 1)
            return value
        }
        let name = visibleNicknames[row]
        let icon = label(prefixes.icon(for: memberModes[current]?[name] ?? []), size: CGFloat(max(fontSize - 3, 9)))
        let nickname = label(name, size: CGFloat(fontSize - 1))
        icon.textColor = color; nickname.textColor = color
        let rowView = NSStackView(views: [icon, nickname]); rowView.orientation = .horizontal; rowView.spacing = 7
        return rowView
    }
    func tableViewSelectionDidChange(_ notification: Notification) { guard (notification.object as? NSTableView) === table, table.selectedRow >= 0, table.selectedRow < channels.count else { return }; current = channels[table.selectedRow]; unread.remove(current); table.reloadData(); render() }
    func ensure(_ channel: String) { if !channels.contains(channel) { channels.append(channel); table.reloadData() } }
    func select(_ channel: String) { ensure(channel); table.selectRowIndexes(IndexSet(integer: channels.firstIndex(of: channel)!),byExtendingSelection: false); current = channel; unread.remove(channel); table.reloadData(); render() }
    func render() {
        title.stringValue = current == "server" ? "DNA / SERVER" : current
        topic.isHidden = !current.hasPrefix("#")
        topic.stringValue = current.hasPrefix("#") ? (topics[current] ?? "No topic set.") : ""
        transcript.textStorage?.setAttributedString(formattedHistory(for: current))
        transcript.scrollToEndOfDocument(nil)
        visibleNicknames = (names[current] ?? []).sorted {
            let left = prefixes.order(for: memberModes[current]?[$0] ?? [])
            let right = prefixes.order(for: memberModes[current]?[$1] ?? [])
            return left == right ? $0.localizedCaseInsensitiveCompare($1) == .orderedAscending : left < right
        }
        members.reloadData()
    }
    func windowDidResize(_ notification: Notification) { window.contentView?.layoutSubtreeIfNeeded(); render() }
    func windowDidBecomeKey(_ notification: Notification) { unread.remove(current); table.reloadData() }
    func modes(for person: String, in channel: String) -> Set<Character> {
        guard let entry = memberModes[channel]?.first(where: { $0.key.caseInsensitiveCompare(person) == .orderedSame }) else { return [] }
        return entry.value
    }
    func nicknameMenu(for row: Int) -> NSMenu? {
        guard registered, current.hasPrefix("#"), visibleNicknames.indices.contains(row) else { return nil }
        let person = visibleNicknames[row], channel = current
        let menu = NSMenu(title: person)
        let heading = NSMenuItem(title: "\(prefixes.icon(for: modes(for: person, in: channel)))  \(person)", action: nil, keyEquivalent: "")
        heading.isEnabled = false; menu.addItem(heading); menu.addItem(.separator())
        func add(_ title: String, _ command: NicknameCommand) {
            let item = menu.addItem(withTitle: title, action: #selector(nicknameAction(_:)), keyEquivalent: "")
            item.target = self; item.tag = command.rawValue; item.representedObject = person
        }
        add("WHOIS", .whois)
        add("Ping", .ping)
        add("Private Chat", .privateChat)
        guard person.caseInsensitiveCompare(nick) != .orderedSame else { return menu }
        let targetModes = modes(for: person, in: channel)
        let permissions = ChannelPermissions(own: modes(for: nick, in: channel), target: targetModes, prefixes: prefixes)
        guard permissions.canModerate else { return menu }
        menu.addItem(.separator())
        if permissions.canVoice { add(targetModes.contains("v") ? "Remove Voice" : "Give Voice", targetModes.contains("v") ? .removeVoice : .giveVoice) }
        if permissions.canHalfOp { add(targetModes.contains("h") ? "Remove Half-Op" : "Give Half-Op", targetModes.contains("h") ? .removeHalfOp : .giveHalfOp) }
        if permissions.canOp { add(targetModes.contains("o") ? "Remove Operator" : "Give Operator", targetModes.contains("o") ? .removeOp : .giveOp) }
        if permissions.canAdmin { add(targetModes.contains("a") ? "Remove Admin" : "Give Admin", targetModes.contains("a") ? .removeAdmin : .giveAdmin) }
        add("Kick from Channel", .kick)
        return menu
    }
    @objc func nicknameAction(_ sender: NSMenuItem) {
        guard registered, current.hasPrefix("#"), let person = sender.representedObject as? String,
              names[current]?.contains(person) == true, let action = NicknameCommand(rawValue: sender.tag) else { return }
        let channel = current
        switch action {
        case .whois:
            whoisDestinations[person.lowercased()] = channel
            client.send("WHOIS \(person)")
        case .ping:
            pingRequests = pingRequests.filter { Date().timeIntervalSince($0.value.started) < 60 }
            let token = UUID().uuidString
            pingRequests[token] = (person, Date(), channel)
            client.send("PRIVMSG \(person) :\u{01}PING \(token)\u{01}")
            append("PING", "Request sent to \(person)", channel: channel)
        case .privateChat:
            select(person); window.makeFirstResponder(input)
        case .kick:
            guard mayModerate(person, in: channel) else { return }
            let alert = NSAlert(); alert.messageText = "Kick \(person) from \(channel)?"
            alert.addButton(withTitle: "Kick"); alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            client.send("KICK \(channel) \(person) :Removed by \(nick)")
        default:
            guard mayModerate(person, in: channel) else { return }
            let mode: String
            switch action {
            case .giveVoice: mode = "+v"
            case .removeVoice: mode = "-v"
            case .giveHalfOp: mode = "+h"
            case .removeHalfOp: mode = "-h"
            case .giveOp: mode = "+o"
            case .removeOp: mode = "-o"
            case .giveAdmin: mode = "+a"
            case .removeAdmin: mode = "-a"
            default: return
            }
            let permissions = ChannelPermissions(own: modes(for: nick, in: channel), target: modes(for: person, in: channel), prefixes: prefixes)
            guard (mode.hasSuffix("v") && permissions.canVoice) || (mode.hasSuffix("h") && permissions.canHalfOp) || (mode.hasSuffix("o") && permissions.canOp) || (mode.hasSuffix("a") && permissions.canAdmin) else { return }
            client.send("MODE \(channel) \(mode) \(person)")
        }
    }
    func mayModerate(_ person: String, in channel: String) -> Bool {
        person.caseInsensitiveCompare(nick) != .orderedSame && ChannelPermissions(own: modes(for: nick, in: channel), target: modes(for: person, in: channel), prefixes: prefixes).canModerate
    }
    func updateMode(_ params: [String]) {
        guard params.count >= 3, params[0].hasPrefix("#") else { return }
        let channel = params[0], args = Array(params.dropFirst(2))
        var adding = true, argument = 0
        for mode in params[1] {
            if mode == "+" { adding = true; continue }
            if mode == "-" { adding = false; continue }
            let memberMode = prefixes.modes.contains(mode)
            let group = channelModeGroups.firstIndex(where: { $0.contains(mode) })
            let takesArgument = memberMode || group == 0 || group == 1 || (group == 2 && adding)
            guard takesArgument else { continue }
            guard argument < args.count else { break }
            let value = args[argument]; argument += 1
            guard memberMode else { continue }
            if adding { names[channel, default: []].insert(value); memberModes[channel, default: [:]][value, default: []].insert(mode) }
            else { memberModes[channel]?[value]?.remove(mode) }
        }
        if channel == current { render() }
    }
    func useNickname(_ value: String) {
        nick = value
        lastUsedNick = value
        UserDefaults.standard.set(value, forKey: "lastConfiguredNick")
        identity.stringValue = "● \(value)"
        identity.isHidden = false
        nickField.stringValue = value
    }
    func formattedHistory(for channel: String) -> NSAttributedString {
        let result = NSMutableAttributedString(string: "")
        let font = mono(CGFloat(fontSize))
        let charWidth = ("M" as NSString).size(withAttributes: [.font: font]).width
        let width = max(180, transcript.bounds.width - transcript.textContainerInset.width * 2)
        let nickWidth = max(3, min(16, Int(width * 0.48 / charWidth) - 9))
        let shadow = NSShadow(); shadow.shadowColor = color.withAlphaComponent(0.45); shadow.shadowBlurRadius = glow
        for entry in histories[channel] ?? [] {
            let sender = entry.sender.count > nickWidth ? String(entry.sender.prefix(nickWidth - 1)) + "…" : entry.sender
            let prefix = entry.time + "  " + sender.padding(toLength: nickWidth, withPad: " ", startingAt: 0) + "  "
            let indent = (prefix as NSString).size(withAttributes: [.font: font]).width
            let paragraph = NSMutableParagraphStyle()
            paragraph.firstLineHeadIndent = 0; paragraph.headIndent = indent; paragraph.lineBreakMode = .byWordWrapping
            let parts = entry.message.components(separatedBy: "\n")
            for (index, part) in parts.enumerated() {
                let lineStyle = paragraph.mutableCopy() as! NSMutableParagraphStyle
                if index > 0 { lineStyle.firstLineHeadIndent = indent }
                result.append(NSAttributedString(string: (index == 0 ? prefix : "") + part + "\n", attributes: [.font: font, .foregroundColor: color, .shadow: shadow, .paragraphStyle: lineStyle]))
            }
            result.append(NSAttributedString(string: "\n", attributes: [.font: font]))
        }
        return result
    }
    func append(_ sender: String, _ message: String, channel: String? = nil, activity: Bool = false) {
        let requested = channel ?? current
        let target = channels.first(where: { $0.caseInsensitiveCompare(requested) == .orderedSame }) ?? requested
        ensure(target)
        let formatter = DateFormatter(); formatter.dateFormat = "HH:mm"
        histories[target, default: []].append(ChatEntry(time: formatter.string(from: Date()), sender: sender, message: message))
        if histories[target]!.count > 1500 { histories[target]!.removeFirst(250) }
        if activity && (target != current || window?.isKeyWindow == false) { unread.insert(target); table.reloadData() }
        if target == current { render() }
    }
    func updateConnectionStatus() {
        guard registered, let connectedAt else { return }
        let seconds = max(0, Int(Date().timeIntervalSince(connectedAt)))
        let elapsed = String(format: "%02d:%02d:%02d", seconds / 3600, (seconds / 60) % 60, seconds % 60)
        status.stringValue = "● CONNECTED / \(connectionHost):\(connectionPort) / \(elapsed)"
    }
    @objc func showConnect() {
        let panel = NSPanel(contentRect: NSRect(x: 0,y: 0,width: 540,height: 470),styleMask: [.titled,.closable],backing: .buffered,defer: false); panel.title = "DNA — Connect"; panel.backgroundColor = dark
        let defaults = UserDefaults.standard
        hostField.stringValue = defaults.string(forKey: "host") ?? "irc.libera.chat"; portField.stringValue = defaults.string(forKey: "port") ?? "6697"; nickField.stringValue = lastUsedNick; channelField.stringValue = defaults.string(forKey: "channel") ?? "#dna"; tlsCheck.state = defaults.object(forKey: "tls") == nil || defaults.bool(forKey: "tls") ? .on : .off
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 12; stack.translatesAutoresizingMaskIntoConstraints = false
        networkPicker.removeAllItems()
        networkPicker.addItem(withTitle: "Custom server")
        for network in availableServers { networkPicker.addItem(withTitle: "\(network.name)  ·  \(network.host):\(network.port)") }
        let selectedNetwork = availableServers.firstIndex { $0.host == hostField.stringValue && String($0.port) == portField.stringValue }
        networkPicker.selectItem(at: selectedNetwork.map { $0 + 1 } ?? 0)
        networkPicker.target = self; networkPicker.action = #selector(selectNetwork)
        let networkRow = NSStackView(views: [label("PUBLIC NETWORK",size: 10),networkPicker]); networkRow.orientation = .horizontal
        networkPicker.widthAnchor.constraint(equalToConstant: 320).isActive = true
        stack.addArrangedSubview(networkRow)
        for (name, field) in [("SERVER",hostField),("PORT",portField),("NICKNAME",nickField),("CHANNEL",channelField)] { let row = NSStackView(views: [label(name,size: 10),field]); row.orientation = .horizontal; field.widthAnchor.constraint(equalToConstant: 230).isActive = true; stack.addArrangedSubview(row) }
        stack.addArrangedSubview(tlsCheck)
        let saveServer = NSButton(title: "Add / Update Server…", target: self, action: #selector(saveCurrentServer))
        stack.addArrangedSubview(saveServer)
        let button = NSButton(title: "Connect to network ↗",target: self,action: #selector(connectNow)); button.bezelStyle = .rounded; stack.addArrangedSubview(button)
        let cancel = NSButton(title: "Cancel",target: self,action: #selector(cancelConnect)); cancel.keyEquivalent = "\u{1b}"; stack.addArrangedSubview(cancel)
        panel.contentView!.addSubview(stack); NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: panel.contentView!.leadingAnchor,constant: 25),stack.topAnchor.constraint(equalTo: panel.contentView!.topAnchor,constant: 28),stack.trailingAnchor.constraint(equalTo: panel.contentView!.trailingAnchor,constant: -25)])
        connectPanel = panel; window.beginSheet(panel)
    }
    @objc func cancelConnect() { if let panel = connectPanel { window.endSheet(panel); panel.orderOut(nil) }; connectPanel = nil }
    @objc func saveCurrentServer() {
        let host = hostField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let channel = channelField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let port = Int(portField.stringValue), (1...65535).contains(port),
              host.range(of: "^[A-Za-z0-9.-]+$", options: .regularExpression) != nil,
              channel.isEmpty || channel.range(of: "^#[^ ,:\\r\\n]+$", options: .regularExpression) != nil else {
            let error = NSAlert(); error.messageText = "Enter a valid server, port, and optional #channel."; error.runModal(); return
        }
        let alert = NSAlert(); alert.messageText = "Save server"
        let name = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24)); name.stringValue = host
        alert.accessoryView = name; alert.addButton(withTitle: "Save"); alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let server = IRCNetwork(name: name.stringValue.isEmpty ? host : name.stringValue, host: host, port: port, tls: tlsCheck.state == .on, channel: channel)
        savedServers.removeAll { $0.host.caseInsensitiveCompare(host) == .orderedSame && $0.port == port }
        savedServers.append(server)
        if let data = try? JSONEncoder().encode(savedServers) { UserDefaults.standard.set(data, forKey: "savedServers") }
        networkPicker.removeAllItems(); networkPicker.addItem(withTitle: "Custom server")
        for item in availableServers { networkPicker.addItem(withTitle: "\(item.name)  ·  \(item.host):\(item.port)") }
        networkPicker.selectItem(at: (availableServers.firstIndex { $0.host.caseInsensitiveCompare(host) == .orderedSame && $0.port == port } ?? 0) + 1)
    }
    @objc func selectNetwork() {
        let index = networkPicker.indexOfSelectedItem - 1
        guard availableServers.indices.contains(index) else { return }
        let server = availableServers[index]
        hostField.stringValue = server.host
        portField.stringValue = String(server.port)
        channelField.stringValue = server.channel
        tlsCheck.state = server.tls ? .on : .off
    }
    @objc func connectNow() {
        let host = hostField.stringValue.trimmingCharacters(in: .whitespaces), nickname = nickField.stringValue, channel = channelField.stringValue
        guard let port = UInt16(portField.stringValue), port > 0, host.range(of: "^[A-Za-z0-9.-]+$",options: .regularExpression) != nil, nickname.range(of: "^[A-Za-z_][A-Za-z0-9_\\-]{0,29}$",options: .regularExpression) != nil, (channel.isEmpty || channel.range(of: "^#[^ ,:\\r\\n]+$",options: .regularExpression) != nil) else { let alert = NSAlert(); alert.messageText = "Check the connection details"; alert.informativeText = "Enter a server hostname, port 1–65535, nickname beginning with a letter, and an optional channel beginning with #."; alert.runModal(); return }
        for (key,value) in [("host",host),("port",String(port)),("channel",channel)] { UserDefaults.standard.set(value,forKey: key) }
        connectionHost = host; connectionPort = Int(port); connectedAt = nil; unread.removeAll(); UserDefaults.standard.set(tlsCheck.state == .on, forKey: "tls"); useNickname(nickname); initialChannel = channel; registered = false; names = [:]; memberModes = [:]; prefixes = ChannelPrefixes(); pingRequests = [:]; whoisDestinations = [:]; channels = ["server"]; histories = [:]; topics = [:]; table.reloadData(); cancelConnect(); select("server"); client.connect(host: host,port: port,nick: nick,encrypted: tlsCheck.state == .on)
    }
    @objc func disconnect() { client.send("QUIT :Leaving DNA"); client.disconnect(); registered = false; connectedAt = nil; status.stringValue = "○ DISCONNECTED"; append("—","Disconnected",channel: "server") }
    @objc func submit() {
        let value = input.stringValue; guard !value.isEmpty else { return }; input.stringValue = ""
        if value.lowercased() == "/help" || value.lowercased() == "/h" { append("DNA","/join (/j) #channel · /part (/p) · /nick (/n) name · /msg (/m) nick message · /whois (/w) nick · /quit (/q)\n/me action · /clear · /connect · /help (/h). Right-click a nickname for more actions. Connect with ⌘K."); return }
        if value == "/clear" { histories[current] = nil; render(); return }
        if value == "/connect" { showConnect(); return }
        guard registered else { append("—","Connect to a server before sending messages. Press ⌘K."); input.stringValue = value; return }
        guard value.utf8.count <= 400, !value.contains("\r"), !value.contains("\n") else { append("—","Please keep messages under 400 bytes."); return }
        if value.hasPrefix("/") {
            let parts = value.dropFirst().split(separator: " ",maxSplits: 1).map(String.init); guard let first = parts.first else { append("—","Type /help for commands."); return }; let command = expandedSlashCommand(first), rest = parts.count > 1 ? parts[1] : ""
            switch command {
            case "join": if rest.hasPrefix("#"), !rest.contains(" ") { client.send("JOIN \(rest)") } else { append("—","Usage: /join #channel") }
            case "part": if current.hasPrefix("#") { client.send("PART \(current)") }
            case "nick": if !rest.isEmpty { client.send("NICK \(rest)") }
            case "msg": let args = rest.split(separator: " ",maxSplits: 1).map(String.init); if args.count == 2 { client.send("PRIVMSG \(args[0]) :\(args[1])"); select(args[0]); append(nick,args[1]) }
            case "whois": if !rest.isEmpty && !rest.contains(" ") { whoisDestinations[rest.lowercased()] = current; client.send("WHOIS \(rest)") } else { append("—","Usage: /whois nick") }
            case "me": if current != "server" { client.send("PRIVMSG \(current) :\u{01}ACTION \(rest)\u{01}"); append("* \(nick)",rest) }
            case "quit": disconnect()
            default: append("—","Unknown command. Type /help.")
            }
        } else if current != "server" { client.send("PRIVMSG \(current) :\(value)"); append(nick,value) }
        else { append("—","Join a channel with /join #channel first.") }
    }
    func handle(_ line: String) {
        let m = IRCMessage(line), p = m.params
        if m.command == "NOTICE", p.count >= 2, p[1].hasPrefix("\u{01}PING ") {
            let token = String(p[1].dropFirst(6)).trimmingCharacters(in: CharacterSet(charactersIn: "\u{01}"))
            if let request = pingRequests.removeValue(forKey: token), request.nick.caseInsensitiveCompare(m.nick) == .orderedSame {
                let milliseconds = Int(Date().timeIntervalSince(request.started) * 1000)
                append("PING", "\(m.nick): \(milliseconds) ms", channel: request.channel)
                return
            }
        }
        switch m.command {
        case "005":
            for token in p.dropFirst() {
                prefixes.update(token)
                if token.hasPrefix("CHANMODES=") {
                    let groups = token.dropFirst(10).split(separator: ",", omittingEmptySubsequences: false).map { Set($0) }
                    if groups.count == 4 { channelModeGroups = groups }
                }
            }
            render()
        case "001": registered = true; if let assigned = p.first { useNickname(assigned) }; connectedAt = Date(); updateConnectionStatus(); if !initialChannel.isEmpty { client.send("JOIN \(initialChannel)") }; append("—",p.last ?? line,channel: "server")
        case "PRIVMSG", "NOTICE": guard p.count >= 2 else { return }; let target = p[0].lowercased() == nick.lowercased() ? m.nick : p[0]; let body = p[1]; if body.hasPrefix("\u{01}ACTION ") { append("* \(m.nick)",String(body.dropFirst(8)).trimmingCharacters(in: CharacterSet(charactersIn: "\u{01}")),channel: target, activity: true) } else { append(m.nick,body,channel: m.command == "NOTICE" ? "server" : target, activity: true) }
        case "JOIN": guard let channel = p.first else { return }; names[channel,default: []].insert(m.nick); if m.nick.lowercased() == nick.lowercased() { select(channel) }; append("→","\(m.nick) joined \(channel)",channel: channel)
        case "PART": guard let channel = p.first else { return }; names[channel]?.remove(m.nick); memberModes[channel]?.removeValue(forKey: m.nick); append("←","\(m.nick) left \(channel)",channel: channel); if m.nick.lowercased() == nick.lowercased() { channels.removeAll { $0 == channel }; table.reloadData(); select("server") }
        case "QUIT": for channel in Array(names.keys) where names[channel]?.contains(m.nick) == true { names[channel]?.remove(m.nick); memberModes[channel]?.removeValue(forKey: m.nick); append("←","\(m.nick) quit",channel: channel) }
        case "NICK": guard let newNick = p.first else { return }; for channel in Array(names.keys) where names[channel]?.contains(m.nick) == true { names[channel]?.remove(m.nick); names[channel]?.insert(newNick); memberModes[channel]?[newNick] = memberModes[channel]?.removeValue(forKey: m.nick); append("—","\(m.nick) is now \(newNick)",channel: channel) }; if m.nick.lowercased() == nick.lowercased() { useNickname(newNick); updateConnectionStatus() }
        case "353": guard p.count >= 4 else { return }; let channel = p[2]; for entry in p[3].split(separator: " ") { let member = prefixes.parseName(String(entry)); guard !member.nick.isEmpty else { continue }; names[channel,default: []].insert(member.nick); memberModes[channel,default: [:]][member.nick] = member.modes }; render()
        case "MODE": updateMode(p)
        case "311", "312", "313", "317", "319", "330", "671", "318", "401":
            guard p.count >= 2 else { return }
            let subject = p[1].lowercased(), destination = whoisDestinations[subject] ?? "server"
            let details: String
            switch m.command {
            case "311" where p.count >= 6: details = "\(p[1])  \(p[2])@\(p[3])  \(p[5])"
            case "312" where p.count >= 4: details = "Server: \(p[2])  \(p[3])"
            case "317" where p.count >= 3: details = "Idle: \(p[2]) seconds"
            case "319" where p.count >= 3: details = "Channels: \(p[2])"
            case "330" where p.count >= 3: details = "Account: \(p[2])"
            default: details = p.last ?? line
            }
            append("WHOIS", details, channel: destination)
            if m.command == "318" || m.command == "401" { whoisDestinations.removeValue(forKey: subject) }
        case "332": if p.count >= 3 { topics[p[1]] = p[2]; render() }
        case "TOPIC": if p.count >= 2 { topics[p[0]] = p[1]; render() }
        case "KICK": if p.count >= 2 { names[p[0]]?.remove(p[1]); memberModes[p[0]]?.removeValue(forKey: p[1]); append("—","\(p[1]) was kicked: \(p.last ?? "")",channel: p[0]); if p[1] == nick { channels.removeAll { $0 == p[0] }; table.reloadData(); select("server") } }
        case "366": break
        default: append("server",p.last ?? line,channel: "server")
        }
    }
    @objc func theme(_ sender: NSMenuItem) { applyTheme(sender.tag); UserDefaults.standard.set(sender.tag,forKey: "theme") }
    @objc func changeFontSize(_ sender: NSMenuItem) { applyFontSize(sender.tag); UserDefaults.standard.set(sender.tag, forKey: "fontSize") }
    func applyFontSize(_ size: Int) {
        fontSize = size
        input.font = mono(CGFloat(size))
        members.rowHeight = CGFloat(max(28, size + 15))
        title.font = mono(CGFloat(size + 7))
        topic.font = mono(CGFloat(size - 2))
        table.rowHeight = CGFloat(max(36, size + 22))
        for item in fontSizeItems { item.state = item.tag == size ? .on : .off }
        table.reloadData(); render()
    }
    func applyTheme(_ index: Int) {
        color = index == 1 ? NSColor(calibratedRed: 0.58,green: 0.9,blue: 0.49,alpha: 1) : index == 2 ? NSColor(calibratedWhite: 0.85,alpha: 1) : amber
        func recolor(_ view: NSView) { if let text = view as? NSTextField { text.textColor = color }; view.subviews.forEach(recolor) }
        if let root = window?.contentView { recolor(root) }
        for panel in framedPanels {
            panel.layer?.borderColor = color.withAlphaComponent(0.4).cgColor
            panel.layer?.backgroundColor = color.withAlphaComponent(0.025).cgColor
            panel.layer?.shadowColor = color.cgColor
            panel.layer?.shadowOpacity = glow > 0 ? 0.12 : 0
            panel.layer?.shadowRadius = 7
            panel.layer?.shadowOffset = .zero
        }
        render(); table.reloadData()
    }
    @objc func toggleScan() { crt.enabled.toggle(); UserDefaults.standard.set(!crt.enabled,forKey: "noScan") }
    @objc func toggleGlow() { glow = glow == 0 ? 3 : 0; for panel in framedPanels { panel.layer?.shadowOpacity = glow > 0 ? 0.12 : 0 }; render() }
    @objc func about() { let alert = NSAlert(); alert.messageText = "DNA"; alert.informativeText = "Internet Relay Chat\nA native macOS application.\n\nCRT appearance inspired by cool-retro-term.\nBuilt with AppKit and Network.framework."; alert.runModal() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) { client.disconnect() }
}
let app = NSApplication.shared
let delegate = App()
app.setActivationPolicy(.regular); app.delegate = delegate; app.run()
