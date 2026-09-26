
func check(_ condition: Bool, _ message: String) { if !condition { fatalError(message) } }
let msg = IRCMessage(":alice!user@host PRIVMSG #dna :hello world")
check(msg.nick == "alice" && msg.command == "PRIVMSG" && msg.params == ["#dna", "hello world"], "PRIVMSG parsing")
let tagged = IRCMessage("@time=123 :irc.example 353 me = #dna :@alice +bob")
check(tagged.command == "353" && tagged.params.last == "@alice +bob", "Tagged NAMES parsing")
check(IRCMessage("PING :token").params == ["token"], "PING parsing")
check(IRCMessage(":alice NICK :bob").params == ["bob"], "NICK parsing")
for (short, full) in [("j", "join"), ("p", "part"), ("n", "nick"), ("m", "msg"), ("w", "whois"), ("q", "quit"), ("h", "help")] {
    check(expandedSlashCommand(short) == full && expandedSlashCommand(full) == full, "\(short) command alias")
}
check(expandedSlashCommand("me") == "me", "Action command stays distinct from /m")
var prefixes = ChannelPrefixes()
let owner = prefixes.parseName("~&@%+founder!user@host")
check(owner.nick == "founder" && owner.modes == Set("qaohv") && prefixes.icon(for: owner.modes) == "★", "multi-prefix founder")
check(prefixes.icon(for: prefixes.parseName("&admin").modes) == "◆", "admin icon")
check(prefixes.icon(for: prefixes.parseName("@operator").modes) == "●", "operator icon")
check(prefixes.icon(for: prefixes.parseName("%halfop").modes) == "◐", "half-operator icon")
check(prefixes.icon(for: prefixes.parseName("+voiced").modes) == "✦", "voice icon")
check(prefixes.icon(for: prefixes.parseName("normal").modes) == "○", "normal icon")
prefixes.update("PREFIX=(ov)@+")
check(prefixes.parseName("@+alice").modes == Set("ov"), "server-advertised prefix mapping")
print("PASS: IRC parser cases")
let listener = try NWListener(using: .tcp, on: .any)
let client = IRCClient()
var wire = "", gotMessage = false, finished = false
listener.newConnectionHandler = { connection in
    connection.start(queue: .main)
    func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, _, error in
            if let data { wire += String(decoding: data, as: UTF8.self) }
            if wire.contains("USER dna") && !gotMessage {
                gotMessage = true
                connection.send(content: Data(":local 001 test :Welcome\r\nPING :probe\r\n:alice!u@h PRIVMSG #dna :hello ".utf8), completion: .contentProcessed { _ in
                    connection.send(content: Data("world\r\n".utf8), completion: .contentProcessed { _ in })
                })
            }
            if wire.contains("CAP REQ :multi-prefix") && wire.contains("PONG :probe") && wire.contains("PRIVMSG #dna :reply") { finished = true; print("PASS: TCP registration, PING/PONG, fragmented receive, and outbound messages"); client.disconnect(); listener.cancel() }
            else if error == nil { receive() }
        }
    }
    receive()
}
listener.stateUpdateHandler = { state in if case .ready = state { client.connect(host: "127.0.0.1", port: listener.port!.rawValue, nick: "test", encrypted: false) } }
client.onLine = { line in if line.contains("hello world") { client.send("PRIVMSG #dna :reply") } }
listener.start(queue: .main)
let deadline = Date().addingTimeInterval(8)
while !finished && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
check(finished, "Local IRC integration timed out")
