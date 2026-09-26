func assertMenu(_ condition: Bool, _ message: String) { if !condition { fatalError(message) } }
let controller = App()
controller.registered = true
controller.current = "#dna"
controller.visibleNicknames = ["target"]
controller.names["#dna"] = ["target", "normal", "voice", "op", "admin", "owner"]
func items() -> [String] { controller.nicknameMenu(for: 0)!.items.map(\.title) }
controller.nick = "normal"
assertMenu(items().contains("WHOIS") && items().contains("Ping") && items().contains("Private Chat"), "Everyone gets information and private chat")
assertMenu(!items().contains("Kick from Channel"), "Normal members cannot moderate")
controller.nick = "voice"; controller.memberModes["#dna"] = ["voice": ["v"]]
assertMenu(!items().contains("Kick from Channel"), "Voiced members cannot moderate")
controller.nick = "op"; controller.memberModes["#dna"] = ["op": ["o"]]
assertMenu(items().contains("Give Voice") && items().contains("Give Operator") && items().contains("Kick from Channel"), "Operators get moderation controls")
assertMenu(!items().contains("Give Admin"), "Operators cannot grant admin in the menu")
controller.nick = "admin"; controller.memberModes["#dna"] = ["admin": ["a"], "target": ["o"]]
assertMenu(items().contains("Remove Operator") && !items().contains("Give Admin"), "Admins can moderate operators but not grant admin")
controller.nick = "owner"; controller.memberModes["#dna"] = ["owner": ["q"], "target": ["a"]]
assertMenu(items().contains("Remove Admin"), "Owners can moderate admins")
controller.nick = "normal"; controller.memberModes["#dna"] = ["target": ["a"]]
assertMenu(!items().contains("Kick from Channel"), "Normal members cannot moderate admins")
print("PASS: nickname context menus by live channel rank")
controller.histories = [:]
controller.current = "#dna"
controller.append("alice", "A long message that should wrap in its own message column rather than beneath the nickname.", channel: "#dna")
let layout = controller.formattedHistory(for: "#dna")
let paragraph = layout.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as! NSParagraphStyle
assertMenu(paragraph.headIndent > paragraph.firstLineHeadIndent, "Wrapped messages use hanging indentation")
controller.append("bob", "Private hello", channel: "bob", activity: true)
assertMenu(controller.unread.contains("bob"), "Inactive private chats get unread activity")
controller.current = "bob"; controller.render()
assertMenu(controller.topic.isHidden && controller.topic.stringValue.isEmpty, "Private chats hide channel topics")
controller.connectionHost = "irc.example.org"; controller.connectionPort = 6697; controller.connectedAt = Date().addingTimeInterval(-65)
controller.updateConnectionStatus()
assertMenu(controller.status.stringValue.contains("irc.example.org:6697") && controller.status.stringValue.contains("00:01:"), "Status includes endpoint and duration")
let virtualife = publicNetworks.first { $0.host == "irc.virtualife.org" }!
assertMenu(virtualife.port == 6697 && virtualife.tls && virtualife.channel == "#informatica", "Virtualife preset")
let vip = publicNetworks.first { $0.host == "irc.vipchat.com.br" }!
assertMenu(vip.port == 6667 && !vip.tls, "VIPChat preset")
let decoded = try! JSONDecoder().decode(IRCNetwork.self, from: JSONEncoder().encode(virtualife))
assertMenu(decoded.channel == virtualife.channel && decoded.tls == virtualife.tls, "Saved server settings round-trip")
let cell = controller.tableView(controller.table, viewFor: nil, row: 0) as! NSTextField
assertMenu(cell.textColor == controller.color, "Channel row uses current theme")
print("PASS: wrapping, unread activity, private topics, status, server presets, and theme")
let catalog = loadServerCatalog(from: URL(fileURLWithPath: "Assets/netsplit-servers.json"))
precondition(catalog.count > 1000)
precondition(catalog.contains { $0.host == "irc2.brasirc.com.br" })
let merged = mergedServers(catalog, saved: [])
precondition(Set(merged.map { $0.host.lowercased() }).isSuperset(of: Set(catalog.map { $0.host.lowercased() })))
precondition(Set(merged.map { $0.host.lowercased() + ":" + String($0.port) }).count == merged.count)
let customized = IRCNetwork(name: "My Libera", host: "irc.libera.chat", channel: "#test")
precondition(mergedServers(catalog, saved: [customized]).first { $0.host == customized.host }?.channel == "#test")
print("PASS: complete bundled server catalog, deduplication, and saved overrides")
