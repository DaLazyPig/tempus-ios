import Foundation

/// One of the 65 real airports the map is measured against.
struct Airport: Codable, Hashable, Identifiable {
    let code: String
    let city: String
    let country: String
    let lat: Double
    let lon: Double

    var id: String { code }
}

/// A destination as the routing layer reports it: the airport, its great-circle distance from
/// wherever home currently is, and the study length that would reach it.
struct Destination: Codable, Hashable, Identifiable {
    let code: String
    let city: String
    let country: String
    /// Great-circle kilometres from home, rounded.
    let km: Int
    /// Study minutes that would land here, to the nearest 5.
    let min: Int

    var id: String { code }
}

/// The geography model.
///
/// Flight time is estimated the way flight-time calculators do it: great-circle distance divided
/// by a typical commercial cruise speed, plus a fixed allowance for taxi, climb, descent and
/// approach. The game layer sits on top - one minute of study buys `scale` minutes of block time,
/// so a 50 minute flight reaches ~3,900 km and a 4 hour one is very nearly antipodal.
///
/// Every distance is measured from `home`, so once you land somewhere the whole map - and
/// therefore every future destination - is relative to the new airport.
enum Geography {

    /// Typical commercial cruise speed, km/h.
    static let cruiseKMH: Double = 875
    /// Taxi + climb + descent + approach, in minutes.
    static let overheadMin: Double = 30
    /// Block minutes bought per study minute.
    static let scale: Double = 6

    static let all: [Airport] = [
        Airport(code: "SYD", city: "Sydney", country: "Australia", lat: -33.94, lon: 151.18),
        Airport(code: "CBR", city: "Canberra", country: "Australia", lat: -35.31, lon: 149.20),
        Airport(code: "MEL", city: "Melbourne", country: "Australia", lat: -37.67, lon: 144.84),
        Airport(code: "BNE", city: "Brisbane", country: "Australia", lat: -27.38, lon: 153.12),
        Airport(code: "ADL", city: "Adelaide", country: "Australia", lat: -34.95, lon: 138.53),
        Airport(code: "CNS", city: "Cairns", country: "Australia", lat: -16.89, lon: 145.75),
        Airport(code: "PER", city: "Perth", country: "Australia", lat: -31.94, lon: 115.97),
        Airport(code: "AKL", city: "Auckland", country: "New Zealand", lat: -37.01, lon: 174.79),
        Airport(code: "CHC", city: "Christchurch", country: "New Zealand", lat: -43.49, lon: 172.53),
        Airport(code: "NAN", city: "Nadi", country: "Fiji", lat: -17.76, lon: 177.44),
        Airport(code: "POM", city: "Port Moresby", country: "Papua New Guinea", lat: -9.44, lon: 147.22),
        Airport(code: "DPS", city: "Denpasar", country: "Indonesia", lat: -8.75, lon: 115.17),
        Airport(code: "CGK", city: "Jakarta", country: "Indonesia", lat: -6.13, lon: 106.66),
        Airport(code: "SIN", city: "Singapore", country: "Singapore", lat: 1.36, lon: 103.99),
        Airport(code: "KUL", city: "Kuala Lumpur", country: "Malaysia", lat: 2.75, lon: 101.71),
        Airport(code: "BKK", city: "Bangkok", country: "Thailand", lat: 13.69, lon: 100.75),
        Airport(code: "MNL", city: "Manila", country: "Philippines", lat: 14.51, lon: 121.02),
        Airport(code: "HAN", city: "Hanoi", country: "Vietnam", lat: 21.22, lon: 105.81),
        Airport(code: "HKG", city: "Hong Kong", country: "Hong Kong", lat: 22.31, lon: 113.91),
        Airport(code: "TPE", city: "Taipei", country: "Taiwan", lat: 25.08, lon: 121.23),
        Airport(code: "PVG", city: "Shanghai", country: "China", lat: 31.14, lon: 121.81),
        Airport(code: "PEK", city: "Beijing", country: "China", lat: 40.08, lon: 116.58),
        Airport(code: "ICN", city: "Seoul", country: "South Korea", lat: 37.46, lon: 126.44),
        Airport(code: "HND", city: "Tokyo", country: "Japan", lat: 35.55, lon: 139.78),
        Airport(code: "CTS", city: "Sapporo", country: "Japan", lat: 42.78, lon: 141.69),
        Airport(code: "DEL", city: "Delhi", country: "India", lat: 28.56, lon: 77.10),
        Airport(code: "BOM", city: "Mumbai", country: "India", lat: 19.09, lon: 72.87),
        Airport(code: "CMB", city: "Colombo", country: "Sri Lanka", lat: 7.18, lon: 79.88),
        Airport(code: "MLE", city: "Malé", country: "Maldives", lat: 4.19, lon: 73.53),
        Airport(code: "DXB", city: "Dubai", country: "UAE", lat: 25.25, lon: 55.36),
        Airport(code: "DOH", city: "Doha", country: "Qatar", lat: 25.27, lon: 51.61),
        Airport(code: "IST", city: "Istanbul", country: "Türkiye", lat: 41.28, lon: 28.75),
        Airport(code: "TLV", city: "Tel Aviv", country: "Israel", lat: 32.01, lon: 34.89),
        Airport(code: "CAI", city: "Cairo", country: "Egypt", lat: 30.11, lon: 31.41),
        Airport(code: "NBO", city: "Nairobi", country: "Kenya", lat: -1.32, lon: 36.93),
        Airport(code: "JNB", city: "Johannesburg", country: "South Africa", lat: -26.14, lon: 28.25),
        Airport(code: "CPT", city: "Cape Town", country: "South Africa", lat: -33.97, lon: 18.60),
        Airport(code: "LOS", city: "Lagos", country: "Nigeria", lat: 6.58, lon: 3.32),
        Airport(code: "CMN", city: "Casablanca", country: "Morocco", lat: 33.37, lon: -7.59),
        Airport(code: "MAD", city: "Madrid", country: "Spain", lat: 40.47, lon: -3.56),
        Airport(code: "CDG", city: "Paris", country: "France", lat: 49.01, lon: 2.55),
        Airport(code: "LHR", city: "London", country: "United Kingdom", lat: 51.47, lon: -0.45),
        Airport(code: "FRA", city: "Frankfurt", country: "Germany", lat: 50.04, lon: 8.56),
        Airport(code: "AMS", city: "Amsterdam", country: "Netherlands", lat: 52.31, lon: 4.76),
        Airport(code: "FCO", city: "Rome", country: "Italy", lat: 41.80, lon: 12.25),
        Airport(code: "ARN", city: "Stockholm", country: "Sweden", lat: 59.65, lon: 17.92),
        Airport(code: "KEF", city: "Reykjavík", country: "Iceland", lat: 63.99, lon: -22.62),
        Airport(code: "SVO", city: "Moscow", country: "Russia", lat: 55.97, lon: 37.41),
        Airport(code: "JFK", city: "New York", country: "United States", lat: 40.64, lon: -73.78),
        Airport(code: "YYZ", city: "Toronto", country: "Canada", lat: 43.68, lon: -79.63),
        Airport(code: "YVR", city: "Vancouver", country: "Canada", lat: 49.19, lon: -123.18),
        Airport(code: "ORD", city: "Chicago", country: "United States", lat: 41.98, lon: -87.90),
        Airport(code: "DFW", city: "Dallas", country: "United States", lat: 32.90, lon: -97.04),
        Airport(code: "LAX", city: "Los Angeles", country: "United States", lat: 33.94, lon: -118.41),
        Airport(code: "SFO", city: "San Francisco", country: "United States", lat: 37.62, lon: -122.38),
        Airport(code: "SEA", city: "Seattle", country: "United States", lat: 47.45, lon: -122.31),
        Airport(code: "HNL", city: "Honolulu", country: "United States", lat: 21.32, lon: -157.92),
        Airport(code: "ANC", city: "Anchorage", country: "United States", lat: 61.17, lon: -149.99),
        Airport(code: "MEX", city: "Mexico City", country: "Mexico", lat: 19.44, lon: -99.07),
        Airport(code: "PTY", city: "Panama City", country: "Panama", lat: 9.07, lon: -79.38),
        Airport(code: "BOG", city: "Bogotá", country: "Colombia", lat: 4.70, lon: -74.15),
        Airport(code: "LIM", city: "Lima", country: "Peru", lat: -12.02, lon: -77.11),
        Airport(code: "GRU", city: "São Paulo", country: "Brazil", lat: -23.43, lon: -46.47),
        Airport(code: "EZE", city: "Buenos Aires", country: "Argentina", lat: -34.82, lon: -58.54),
        Airport(code: "SCL", city: "Santiago", country: "Chile", lat: -33.39, lon: -70.79)
    ]

    // MARK: - Home

    /// Where the map is measured from. Landing somewhere reassigns this, which is the one rule
    /// the whole metaphor rests on.
    private(set) static var home: Airport = Geography.all[0]

    /// The code the destination list was built from, so a stale list can never outlive a change
    /// of home airport.
    private static var builtFrom: String?
    private static var destinationCache: [Destination] = []

    static func setHome(_ code: String) {
        home = byCode(code)
        rebuild()
    }

    static func byCode(_ code: String) -> Airport {
        all.first { $0.code == code } ?? all[0]
    }

    // MARK: - Distance

    private static func rad(_ d: Double) -> Double { d * .pi / 180 }

    /// Haversine great-circle distance in kilometres, on a 6371 km sphere.
    static func greatCircle(_ a: Airport, _ b: Airport) -> Double {
        let dLat = rad(b.lat - a.lat), dLon = rad(b.lon - a.lon)
        let h = sin(dLat / 2) * sin(dLat / 2)
            + cos(rad(a.lat)) * cos(rad(b.lat)) * sin(dLon / 2) * sin(dLon / 2)
        return 6371 * 2 * asin(min(1, sqrt(h)))
    }

    static func distanceBetween(_ a: String, _ b: String) -> Double {
        greatCircle(byCode(a), byCode(b))
    }

    /// Study minutes to great-circle kilometres.
    static func km(forMinutes minutes: Int) -> Double {
        max(40, (Double(max(1, minutes)) * scale - overheadMin) / 60 * cruiseKMH)
    }

    /// And back again, so a destination can quote the flight it would take. To the nearest 5.
    static func minutes(forKm km: Double) -> Int {
        let raw = (km / cruiseKMH * 60 + overheadMin) / scale / 5
        return max(5, Int(raw.rounded(.toNearestOrAwayFromZero)) * 5)
    }

    // MARK: - Destinations

    /// Everything reachable from where you are now, nearest first.
    @discardableResult
    static func rebuild() -> [Destination] {
        let h = home
        builtFrom = h.code
        destinationCache = all
            .filter { $0.code != h.code }
            .map { ap in
                let d = greatCircle(h, ap)
                return Destination(code: ap.code, city: ap.city, country: ap.country,
                                   km: Int(d.rounded()), min: minutes(forKm: d))
            }
            .sorted { $0.km < $1.km }
        return destinationCache
    }

    /// Self-healing: if home moved without anyone calling `rebuild`, rebuild now rather than
    /// measuring a new origin's distances against the old origin's table.
    static var destinations: [Destination] {
        if destinationCache.isEmpty || builtFrom != home.code { return rebuild() }
        return destinationCache
    }

    /// The destination whose real distance best fits the flight you just booked - the smallest
    /// *relative* error, not the smallest absolute one, so short flights are not all swallowed by
    /// whichever airport happens to be nearest.
    static func destination(forMinutes minutes: Int) -> Destination {
        let list = destinations
        let target = km(forMinutes: minutes)
        var best = list[0]
        var bestErr = Double.infinity
        for d in list {
            let err = abs(Double(d.km) - target) / target
            if err < bestErr { bestErr = err; best = d }
        }
        return best
    }
}
