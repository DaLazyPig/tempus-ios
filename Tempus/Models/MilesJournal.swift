import Foundation

/// Personal spending stays local. This ordered outbox reconciles it before a transfer.
/// A restored copy keeps the same stream; competing edits at one sequence are a conflict,
/// never last-write-wins. Server-confirmed gifts change miles without creating a local earn.
struct MilesJournal: Codable {
    struct Entry: Codable, Equatable {
        var id = UUID()
        var seq: Int
        var delta: Int
        var at: TimeInterval
    }

    var wallet = UUID()
    var owner: String?
    private(set) var sequence = 0
    private(set) var pending: [Entry] = []
    private(set) var received: Set<String> = []

    init(balance: Int) {
        // A one-time import preserves pre-journal miles. The server bounds this migration
        // and allows only one wallet per account; it is not proof of historical study.
        append(balance)
    }

    mutating func append(_ delta: Int, at: TimeInterval = Date().timeIntervalSince1970) {
        guard delta != 0 || sequence == 0 else { return }
        sequence += 1
        pending.append(Entry(seq: sequence, delta: delta, at: at))
    }

    /// Adopt the stream this account actually holds, abandoning one the server has never seen.
    /// Only `AppModel.repairMilesWallet` calls this, and only after `my_wallet()` has named the
    /// stream — never as a guess. `pending` goes with the old wallet because those entries are
    /// sequenced against it; the visible balance is `AppModel.miles` and is untouched.
    mutating func adopt(wallet: UUID, sequence: Int, owner: String) {
        self.wallet = wallet
        self.sequence = sequence
        self.owner = owner
        pending.removeAll()
    }

    mutating func acknowledge(through sequence: Int) {
        pending.removeAll { $0.seq <= sequence }
    }

    mutating func receive(_ gift: String) -> Bool {
        received.insert(gift.lowercased()).inserted
    }
}

/// Persisted BEFORE reserving funds or starting the request. A timeout is unresolved,
/// not a rejection: retry these exact bytes and the same operation id after reconnecting.
struct PendingGift: Codable {
    var order: Order
    var owner: String
    var wallet: UUID
    var entries: [MilesJournal.Entry]
    var sequence: Int
    var personal: Int
    var pair: String?
    var fromName: String
}

#if DEBUG
func milesJournalSelfCheck() {
    var journal = MilesJournal(balance: 100)
    journal.append(20)
    journal.append(-10)
    let snapshot = journal.pending
    journal.append(-5) // An offline spend while the earlier batch is in flight.
    journal.acknowledge(through: snapshot.last!.seq)
    assert(journal.pending.count == 1 && journal.pending[0].delta == -5)
    assert(journal.sequence == 4)
    let restored = try! JSONDecoder().decode(MilesJournal.self, from: JSONEncoder().encode(journal))
    assert(restored.wallet == journal.wallet && restored.pending == journal.pending)
    var adopted = journal
    let serverWallet = UUID()
    adopted.adopt(wallet: serverWallet, sequence: 9, owner: "acct")
    assert(adopted.wallet == serverWallet && adopted.sequence == 9 && adopted.pending.isEmpty,
           "adopting the account's stream must drop an outbox the server has never seen")
    adopted.append(-3)
    assert(adopted.pending.count == 1 && adopted.pending[0].seq == 10,
           "the next local movement continues the adopted stream, not the abandoned one")
    let gift = UUID().uuidString
    assert(journal.receive(gift))
    assert(!journal.receive(gift.lowercased()), "a replay must not credit the phone twice")
    let afterReceipt = try! JSONDecoder().decode(MilesJournal.self, from: JSONEncoder().encode(journal))
    assert(afterReceipt.received == journal.received, "receipt and balance must survive together")
}
#endif
