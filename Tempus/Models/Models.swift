import Foundation

/// A subject on the deck. Flying one spends it: a landed task is removed.
struct TaskItem: Codable, Hashable, Identifiable {
    var id: String
    var title: String
    /// The miles the card advertises. Display only; the flight pays `Status.earn`.
    var miles: Int
}

/// A flight, as kept in the archive.
///
/// **A pass is a document.** `AppModel.logFlight` is the single writer, so a landing and a divert
/// produce the same record, and it freezes the livery and the pass header into it. Nothing may
/// recompute a past flight's livery — the route table is allowed to change, the archive is not.
///
/// The reference stores the carrier's name, code, colours and typeface too, then rewrites all four
/// on read (`TempusCarriers.normalize`) because aeroTempus is now the only carrier. Storing values
/// that are overwritten on every read is not storage, so this record keeps only what actually
/// varies per flight — the livery, the header and the aircraft — and derives the rest.
struct FlightRecord: Codable, Hashable, Identifiable {
    var id: String
    /// Epoch seconds.
    var t: TimeInterval
    var from: String
    var fromCity: String
    var to: String
    var toCity: String
    var country: String
    var minutes: Int
    var miles: Int
    var diverted: Bool
    var subject: String
    /// The flight number, e.g. `TP 0842`.
    var no: String
    var ac: String
    /// The frozen livery.
    var pat: Carriers.Livery
    /// The frozen pass header id, when one was flown.
    var hdr: String?
    var milestone: Milestone?

    var carrierName: String { Carriers.name }
    var iata: String { Carriers.iata }

    enum Milestone: String, Codable, Hashable {
        case first, country, hundred, four, long
    }
}

/// The milestone ledger. Milestones are judged against this rather than against the flights array,
/// so none can ever be awarded twice. A diverted flight does not advance it at all — not even
/// `count`.
struct Marks: Codable, Hashable {
    var first: Bool = false
    var countries: [String] = []
    var longestMin: Int = 0
    var count: Int = 0
    var four: Bool = false
}

/// An unlock in progress: miles already spent, buying screen time on one app until `until`.
struct Unlock: Codable, Hashable {
    var id: String
    var name: String
    /// Total miles committed, summed across extensions.
    var cost: Int
    var mins: Int
    var until: TimeInterval

    var expired: Bool { until <= Date().timeIntervalSince1970 }
}

/// One line of the miles statement. Shop purchases record `mins: 0`.
struct SpendEntry: Codable, Hashable, Identifiable {
    var id: TimeInterval { t }
    var t: TimeInterval
    var label: String
    var mins: Int
    var cost: Int
}

/// A linked member. Linked members hold one bank: a spend takes what it can from your own balance
/// and the rest from theirs, so the pool is what either of you can spend.
///
/// **A link can be pending.** There is no backend to deliver a request to a second person (see
/// `Backend.swift` — it backs up one member's own blob, nothing more), so a request this device
/// sends is real and honest but cannot yet be accepted anywhere but here. `pending` and
/// `requestedByThem` are both optional so a blob saved before either field existed decodes as an
/// established link (`pending == nil` reads as accepted) — every link made before this shipped
/// was instant, so treating its absence as "already agreed" is the only backward-compatible
/// reading. While pending, nothing is shared: `AppModel.pool` and `unlockAllowance` must not count
/// a pending partner's `miles`.
struct LinkAccount: Codable, Hashable {
    var name: String
    var email: String?
    var miles: Int
    /// Epoch seconds the link was made (or requested).
    var at: TimeInterval
    var log: [Entry] = []
    /// `nil`/`false` — an established, shared bank. `true` — a request awaiting the other side.
    var pending: Bool?
    /// Only meaningful while `pending`. `true` — the other member asked to link with you, and this
    /// device owes an accept/decline. `nil`/`false` — this device sent the request and is waiting.
    var requestedByThem: Bool?

    var isPending: Bool { pending == true }
    var isIncomingRequest: Bool { pending == true && requestedByThem == true }

    struct Entry: Codable, Hashable, Identifiable {
        var id: TimeInterval { t }
        var t: TimeInterval
        var n: Int
        var label: String
        var meta: String
    }
}

/// A gift sent from the Concourse, kept on the SENDER's device.
struct SentGift: Codable, Hashable, Identifiable {
    var id: TimeInterval { t }
    var t: TimeInterval
    var who: String
    var email: String?
    var amt: Int
    var face: String?
}

/// A gift awaiting accept/decline on the RECIPIENT's device. Populated from the server
/// (`AppModel.refreshGifts`, via `Backend.openGifts`) or, in DEBUG, a launch seam — the two things
/// that can address a device with nothing pushed to it. Accepting one credits `AppModel.miles`
/// through `acceptGift`, the one place a gift's miles arrive.
struct ReceivedGift: Codable, Hashable, Identifiable {
    var id: TimeInterval { t }
    var t: TimeInterval
    var from: String
    var amt: Int
    var face: String?
    /// The server row's own id, when this gift came from `refreshGifts` rather than a local seam.
    /// `acceptGift`/`declineGift` answer the server when this is set and stay purely local — the
    /// old, synchronous behaviour — when it is nil, which is what keeps `seedIncomingRequest` and
    /// `giftSelfCheck` working unchanged.
    var remoteID: String? = nil
}

/// One credit to the balance that is not a flight and not a spend — today, only an accepted gift.
/// Kept separate from `SpendEntry` (which always records miles leaving) so a credit is never a
/// spend wearing a negative sign; `StatusScreen`'s statement folds both into one ledger.
struct CreditEntry: Codable, Hashable, Identifiable {
    var id: TimeInterval { t }
    var t: TimeInterval
    var label: String
    var amt: Int
}

/// What a purchase is for. Concourse stock is granted outright; an unlock starts a clock;
/// `apps` is a change to the blocked-app selection, which grants nothing but the change itself.
enum PurchaseKind: String, Codable, Hashable {
    case unlock, face, header, gift, apps
}

/// An order handed to `AppModel.payOrder` — the only place miles leave the balance.
struct Order: Codable, Hashable, Identifiable {
    var id = UUID()
    var kind: PurchaseKind
    var cost: Int
    var name: String
    /// The app id for an unlock, or the shop id for stock.
    var itemID: String?
    var mins: Int = 0
    /// True when this adds time to the unlock already running on the same app.
    var extend: Bool = false
    /// Gift only.
    var who: String?
    var whoEmail: String?
    var amt: Int = 0
    var face: String?
}

/// A blockable app. The reference's Lucide glyph names are carried through and mapped to SF Symbols
/// at the point of drawing.
struct BlockableApp: Identifiable, Hashable {
    let id: String
    let label: String
    let icon: String

    static let all: [BlockableApp] = [
        BlockableApp(id: "ig", label: "Instagram", icon: "instagram"),
        BlockableApp(id: "tt", label: "TikTok", icon: "music"),
        BlockableApp(id: "yt", label: "YouTube", icon: "youtube"),
        BlockableApp(id: "rd", label: "Reddit", icon: "message-circle"),
        BlockableApp(id: "sc", label: "Snapchat", icon: "ghost"),
        BlockableApp(id: "mu", label: "Music", icon: "music")
    ]

    static func named(_ id: String) -> BlockableApp? { all.first { $0.id == id } }
}
