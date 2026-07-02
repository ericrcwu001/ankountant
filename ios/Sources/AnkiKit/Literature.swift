import Foundation

// The client-bundled, per-section authoritative-literature corpus (T2 / OQ-3:
// search is client-side over this bundled data). This decodes the app resource
// `seed_literature.json`, which is a verbatim copy of the backend source of
// truth `rslib/src/ankountant/seed_literature.json` — keep the two in sync.
//
// Per ADR 0006 / ADR 0008 / D10 the corpus is per-body:
//  - FASB ASC (FAR/BAR): `verbatim:false` — OUR paraphrase + a deep link;
//    verbatim ASC prose is NEVER shipped (Tier-B firewall).
//  - IRC/PCAOB/NIST (REG/TCP/AUD/ISC): `verbatim:true` — real public-domain text.

/// One authoritative-literature passage. Mirrors the desktop `CorpusEntry` and
/// the Rust `LiteratureEntry` (the JSON `deep_link` snake_case is mapped).
public struct CorpusEntry: Sendable, Identifiable, Equatable, Decodable {
    public let id: String
    public let citation: String
    public let title: String
    /// Paraphrase (cite-only) OR real verbatim public-domain text.
    public let body: String
    public let deepLink: String?
    public let verbatim: Bool
    public let tags: [String]

    enum CodingKeys: String, CodingKey {
        case id, citation, title, body, verbatim, tags
        case deepLink = "deep_link"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        citation = try container.decode(String.self, forKey: .citation)
        title = try container.decode(String.self, forKey: .title)
        body = try container.decode(String.self, forKey: .body)
        deepLink = try container.decodeIfPresent(String.self, forKey: .deepLink)
        verbatim = (try? container.decode(Bool.self, forKey: .verbatim)) ?? false
        tags = (try? container.decode([String].self, forKey: .tags)) ?? []
    }

    public init(
        id: String,
        citation: String,
        title: String,
        body: String,
        deepLink: String? = nil,
        verbatim: Bool = false,
        tags: [String] = []
    ) {
        self.id = id
        self.citation = citation
        self.title = title
        self.body = body
        self.deepLink = deepLink
        self.verbatim = verbatim
        self.tags = tags
    }
}

/// Decode the bundled per-section corpus from the AnkiKit resource. Returns an
/// empty map if the resource is missing or malformed (the pane then reads as
/// "no literature bundled" rather than crashing).
public func loadLiteratureCorpus() -> [String: [CorpusEntry]] {
    guard let url = Bundle.module.url(forResource: "seed_literature", withExtension: "json"),
          let data = try? Data(contentsOf: url),
          let decoded = try? JSONDecoder().decode([String: [CorpusEntry]].self, from: data)
    else {
        return [:]
    }
    return decoded
}

/// The bundled corpus passages for a section (empty for an unseeded section).
public func corpusForSection(_ corpus: [String: [CorpusEntry]], _ section: String) -> [CorpusEntry] {
    corpus[section] ?? []
}

/// Substring/keyword search over `citation + title + body + tags` (T2 AC1). An
/// empty query returns everything (the corpus is small + scoped), so the pane
/// reads as a browsable reference, not a blank box. Mirrors the desktop
/// `searchCorpus`.
public func searchCorpus(_ entries: [CorpusEntry], query: String) -> [CorpusEntry] {
    let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if q.isEmpty { return entries }
    let terms = q.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    return entries.filter { entry in
        let hay = "\(entry.citation) \(entry.title) \(entry.body) \(entry.tags.joined(separator: " "))"
            .lowercased()
        return terms.allSatisfy { hay.contains($0) }
    }
}
