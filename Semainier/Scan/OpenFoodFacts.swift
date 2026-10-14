import Foundation

/// Produit lu sur Open Food Facts, déjà converti en brouillon d'ingrédient.
nonisolated struct ScannedProduct {
    var name: String
    /// Contenance affichée, ex. « 4 x 100 g ».
    var quantity = ""
    var unit: Unit
    var kcal: Double?
    var p: Double?
    var c: Double?
    var f: Double?
    var rayon: Rayon
    /// Rempli quand les kcal de la fiche ont été écartées car incohérentes.
    var kcalNote: String?
    /// Poids d'une pièce déduit de la contenance (« 300 g », « 4 x 125 g »).
    var pieceWeight: Double?
}

nonisolated enum OpenFoodFacts {
    enum LookupError: Error { case network }

    /// Nil si le produit est inconnu. Lève `.network` si la requête échoue.
    static func lookup(_ code: String) async throws -> ScannedProduct? {
        var comps = URLComponents(string: "https://world.openfoodfacts.org/api/v2/product/\(code).json")!
        comps.queryItems = [URLQueryItem(name: "fields", value: "product_name,product_name_fr,brands,nutriments,quantity,categories_tags")]
        var req = URLRequest(url: comps.url!, timeoutInterval: 12)
        // Open Food Facts demande un User-Agent identifiant l'appli.
        req.setValue("Semainier/1.0 (iOS, usage personnel)", forHTTPHeaderField: "User-Agent")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            throw LookupError.network
        }
        if let http = response as? HTTPURLResponse, http.statusCode == 404 { return nil }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (json["status"] as? Int) == 1,
              let product = json["product"] as? [String: Any]
        else { return nil }
        return parse(product)
    }

    /// Produits proches (même nom / marque), vendus en France, les plus scannés d'abord.
    /// Sans doublons : deux produits aux valeurs identiques ne comptent qu'une fois.
    static func search(_ terms: String, excluding code: String? = nil) async throws -> [ScannedProduct] {
        var comps = URLComponents(string: "https://world.openfoodfacts.org/cgi/search.pl")!
        comps.queryItems = [
            URLQueryItem(name: "search_terms", value: terms),
            URLQueryItem(name: "search_simple", value: "1"),
            URLQueryItem(name: "json", value: "1"),
            URLQueryItem(name: "page_size", value: "24"),
            URLQueryItem(name: "sort_by", value: "unique_scans_n"),
            URLQueryItem(name: "tagtype_0", value: "countries"),
            URLQueryItem(name: "tag_contains_0", value: "contains"),
            URLQueryItem(name: "tag_0", value: "france"),
            URLQueryItem(name: "fields", value: "code,product_name,product_name_fr,brands,nutriments,quantity,categories_tags"),
        ]
        var req = URLRequest(url: comps.url!, timeoutInterval: 15)
        req.setValue("Semainier/1.0 (iOS, usage personnel)", forHTTPHeaderField: "User-Agent")

        let data: Data
        do {
            (data, _) = try await URLSession.shared.data(for: req)
        } catch {
            throw LookupError.network
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let products = json["products"] as? [[String: Any]]
        else { return [] }

        var seen = Set<String>()
        return products.compactMap { raw in
            if let code, (raw["code"] as? String) == code { return nil }
            let p = parse(raw)
            guard !p.name.isEmpty, p.kcal != nil || p.p != nil else { return nil }
            let key = [p.name.lowercased(), "\(p.kcal ?? -1)", "\(p.p ?? -1)", "\(p.c ?? -1)", "\(p.f ?? -1)"].joined(separator: "|")
            return seen.insert(key).inserted ? p : nil
        }
    }

    static func parse(_ product: [String: Any]) -> ScannedProduct {
        let n = product["nutriments"] as? [String: Any] ?? [:]
        func num(_ key: String) -> Double? {
            if let d = n[key] as? Double { return d }
            if let i = n[key] as? Int { return Double(i) }
            if let s = n[key] as? String { return Fmt.parse(s) }
            return nil
        }
        let p = num("proteins_100g"), c = num("carbohydrates_100g"), f = num("fat_100g")
        let macroKcal: Double? = (p != nil || c != nil || f != nil)
            ? Macros(p: p ?? 0, c: c ?? 0, f: f ?? 0).kcalFromMacros : nil
        // `energy_100g` est toujours en kJ sur Open Food Facts.
        let shownKcal = num("energy-kcal_100g")
        let kj = num("energy-kj_100g") ?? num("energy_100g")
        let resolved = Nutrition.resolveKcal(kcal: shownKcal, kj: kj, macroKcal: macroKcal)
        let kcal = resolved.value
        let kcalNote = resolved.corrected
            ? "Kcal corrigées : la fiche indiquait \(Fmt.n0(shownKcal ?? 0)) kcal, incohérent avec ses \(Fmt.n0(kj ?? 0)) kJ et ses macros."
            : nil

        let base = [product["product_name_fr"], product["product_name"]]
            .compactMap { ($0 as? String)?.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? ""
        let brand = (product["brands"] as? String)?
            .split(separator: ",").first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        let name = [base, brand].filter { !$0.isEmpty }.joined(separator: " · ")

        let quantity = (product["quantity"] as? String ?? "").lowercased()
        let isLiquid = quantity.range(of: #"\d\s*(ml|cl|dl|l)\b"#, options: .regularExpression) != nil

        return ScannedProduct(
            name: name,
            quantity: product["quantity"] as? String ?? "",
            unit: isLiquid ? .ml : .g,
            kcal: kcal.map { ($0 * 10).rounded() / 10 },
            p: p,
            c: c,
            f: f,
            rayon: rayon(for: product["categories_tags"] as? [String] ?? []),
            kcalNote: kcalNote,
            pieceWeight: pieceWeight(from: product["quantity"] as? String ?? "")
        )
    }

    /// Poids ou volume d'une pièce à partir de la contenance : « 300 g » → 300, « 4 x 125 g » → 125,
    /// « 33 cl » → 330, « 1,5 L » → 1500. Nil si illisible.
    static func pieceWeight(from quantity: String) -> Double? {
        let q = quantity.lowercased().replacingOccurrences(of: ",", with: ".")
        let pattern = #"(?:(\d+)\s*[x×]\s*)?(\d+(?:\.\d+)?)\s*(kg|g|mg|cl|ml|dl|l)\b"#
        guard let m = q.firstMatch(of: try! Regex(pattern)),
              let value = m.output[2].substring.flatMap({ Double($0) }),
              let unit = m.output[3].substring.map(String.init) else { return nil }
        let factor: Double = ["kg": 1000, "g": 1, "mg": 0.001, "l": 1000, "dl": 100, "cl": 10, "ml": 1][unit] ?? 1
        let w = value * factor
        return w > 0 ? w : nil
    }

    /// Devine le rayon à partir des catégories Open Food Facts.
    static func rayon(for tags: [String]) -> Rayon {
        let t = Set(tags)
        func any(_ keys: [String]) -> Bool { keys.contains { t.contains("en:" + $0) } }
        if any(["frozen-foods"]) { return .surgeles }
        if any(["dairies", "cheeses", "yogurts", "eggs", "milks", "butters", "creams"]) { return .cremerieOeufs }
        if any(["meats", "poultries", "fishes", "seafood", "hams", "sausages"]) { return .viandesPoissons }
        if any(["breads", "viennoiseries", "pastries"]) { return .boulangerie }
        if any(["fresh-fruits", "fresh-vegetables", "fruits", "vegetables"]) && !any(["canned-foods"]) { return .fruitsLegumes }
        return .epicerie
    }
}
