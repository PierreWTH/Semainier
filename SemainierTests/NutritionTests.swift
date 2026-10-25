import Foundation
import Testing
@testable import Semainier

struct NutritionTests {
    @Test func macrosPer100g() {
        let oats = Macros(kcal: 367, p: 13.5, c: 58.7, f: 7)
        let m = Nutrition.macros(per: oats, unit: .g, qty: 80)
        #expect(abs(m.kcal - 293.6) < 1e-9)
        #expect(abs(m.p - 10.8) < 1e-9)
    }

    @Test func macrosPerPiece() {
        let egg = Macros(kcal: 80, p: 6.9, c: 0.4, f: 5.6)
        #expect(Nutrition.macros(per: egg, unit: .pc, qty: 3).kcal == 240)
    }

    @Test func stepper() {
        #expect(Nutrition.stepped(1, by: 1) == 1.1)
        #expect(Nutrition.stepped(1.15, by: -1) == 1.05)
        #expect(Nutrition.stepped(0.1, by: -1) == 0.1)
    }

    @Test func aggregate() {
        let r = Nutrition.aggregate([(key: "riz", qty: 90), (key: "riz", qty: 54), (key: "œuf", qty: 3)])
        #expect(r["riz"] == 144)
        #expect(r["œuf"] == 3)
    }

    @Test func kcalFromMacros() {
        #expect(Macros(p: 10, c: 20, f: 5).kcalFromMacros == 165)
    }
}

struct FmtTests {
    let nnbsp = "\u{202F}" // espace fine insécable (séparateur de milliers fr)

    @Test func shopRoundsUpTo5() {
        #expect(Fmt.shop(142, unit: .g) == "145 g")
        #expect(Fmt.shop(145, unit: .g) == "145 g")
        #expect(Fmt.shop(100.000_000_1, unit: .g) == "100 g")
        #expect(Fmt.shop(1250, unit: .ml) == "1,25 L")
        #expect(Fmt.shop(998, unit: .g) == "1 kg")
    }

    @Test func shopPieces() {
        #expect(Fmt.shop(0.5, unit: .pc) == "1 pièce")
        #expect(Fmt.shop(2.2, unit: .pc) == "3 pièces")
        #expect(Fmt.shop(3, unit: .pc) == "3 pièces")
    }

    @Test func cook() {
        #expect(Fmt.cook(12.3, unit: .g) == "12 g")
        #expect(Fmt.cook(93, unit: .g) == "95 g")
        #expect(Fmt.cook(1.3, unit: .pc) == "1,5 pièce" + "s")
        #expect(Fmt.cook(0.6, unit: .pc) == "0,5 pièce")
    }

    @Test func numbers() {
        #expect(Fmt.n0(2600) == "2\(nnbsp)600")
        #expect(Fmt.x(1) == "×1,0")
        #expect(Fmt.x(1.15) == "×1,15")
        #expect(Fmt.diff(2720, target: 2600) == "+120 kcal")
        #expect(Fmt.diff(2555, target: 2600) == "−45 kcal")
        #expect(Fmt.diff(2600.4, target: 2600) == "pile")
    }

    @Test func parse() {
        #expect(Fmt.parse("12,5") == 12.5)
        #expect(Fmt.parse(" 1 200 ") == 1200)
        #expect(Fmt.parse("") == nil)
        #expect(Fmt.parse("abc") == nil)
        #expect(Fmt.input(80) == "80")
        #expect(Fmt.input(0.5) == "0,5")
    }
}

/// Fiche Open Food Facts écrite en dictionnaire, passée par le JSON comme une vraie réponse.
private func parseOFF(_ product: [String: Any]) -> ScannedProduct {
    let data = try! JSONSerialization.data(withJSONObject: product)
    return OpenFoodFacts.parse(try! JSONDecoder().decode(OpenFoodFacts.Produit.self, from: data))
}

struct OpenFoodFactsTests {
    @Test func parsesProduct() {
        let p = parseOFF([
            "product_name": "Skyr nature",
            "brands": "Siggi's, Arla",
            "quantity": "450 g",
            "categories_tags": ["en:dairies", "en:yogurts"],
            "nutriments": ["energy-kcal_100g": 64, "proteins_100g": 11.0, "carbohydrates_100g": "4", "fat_100g": 0.2],
        ])
        #expect(p.name == "Skyr nature · Siggi's")
        #expect(p.unit == .g)
        #expect(p.kcal == 64)
        #expect(p.c == 4)
        #expect(p.rayon == .cremerieOeufs)
    }

    @Test func kcalFromKJAndLiquid() {
        let p = parseOFF(["product_name": "Jus", "quantity": "1 L", "nutriments": ["energy_100g": 184.1]])
        #expect(p.unit == .ml)
        #expect(p.kcal == 44)
        #expect(p.rayon == .epicerie)
    }
}

struct BackupTests {
    @Test func decodesMockupFormat() throws {
        let json = """
        {"v":1,"targets":{"kcal":2600,"p":160,"c":310,"f":80},
         "ingredients":[{"id":"a","name":"Riz","unit":"g","kcal":355,"p":8,"c":78,"f":0.9,"rayon":"Épicerie"}],
         "recipes":[{"id":"r","name":"Riz","items":[{"ing":"a","qty":90}]}],
         "plan":{"d0":[{"id":"e","s":1,"r":"r","x":1.2}],"d3":[]},
         "checked":{"a":true},"shopDays":[0,1]}
        """
        let b = try JSONDecoder().decode(Backup.self, from: Data(json.utf8))
        #expect(b.plan.count == 1)
        #expect(b.plan[0].day == 0 && b.plan[0].slot == 1 && b.plan[0].x == 1.2)
        #expect(b.ingredients[0].barcode == nil)
    }
}

struct DaysTests {
    @Test func rangeText() {
        #expect(Days.rangeText(20261015, 20261021) == "du 15 au 21 octobre")
        #expect(Days.rangeText(20260928, 20261004) == "du 28 septembre au 4 octobre")
        #expect(Days.rangeText(20260601, 20260607) == "du 1er au 7 juin")
        #expect(Days.rangeText(20261026, 20261101) == "du 26 octobre au 1er novembre")
    }

    @Test func arithmetic() {
        #expect(Days.adding(1, to: 20261031) == 20261101)
        #expect(Days.adding(-1, to: 20270101) == 20261231)
        #expect(Days.adding(1, to: 20261025) == 20261026)          // changement d'heure
        #expect(Days.distance(from: 20261015, to: 20261022) == 7)
        #expect(Days.distance(from: 20261015, to: 20261008) == -7)
    }

    @Test func labels() {
        #expect(Days.weekdayIndex(20261015) == 3)                   // jeudi
        #expect(Days.shortLabel(20261015) == "Jeu 15")
        #expect(Days.longLabel(20261015) == "Jeudi 15 octobre")
        #expect(Days.relative(20261016, today: 20261015) == "demain")
        #expect(Days.relative(20261020, today: 20261015) == nil)
    }

    @Test func nextWeekdayFromToday() {
        // Aujourd'hui jeudi 15 : jeudi → 15, vendredi → 16, lundi → 19, mercredi → 21.
        #expect(Days.next(weekday: 3, from: 20261015) == 20261015)
        #expect(Days.next(weekday: 4, from: 20261015) == 20261016)
        #expect(Days.next(weekday: 0, from: 20261015) == 20261019)
        #expect(Days.next(weekday: 2, from: 20261015) == 20261021)
    }

    @Test func iso() {
        #expect(Days.iso(20261015) == "2026-10-15")
        #expect(Days.parseISO("2026-10-15") == 20261015)
    }
}

struct KcalCheckTests {
    @Test func stMoretWrongKcalIsCorrectedFromKJ() {
        // Fiche réelle : 765 kcal affichées, 551 kJ, G 5 · P 10 · L 8 (≈ 132 kcal).
        let p = parseOFF([
            "product_name": "St Moret Ligne & Plaisir 8%",
            "nutriments": ["energy-kcal_100g": 765, "energy-kj_100g": 551, "energy_100g": 551,
                           "proteins_100g": 10, "carbohydrates_100g": 5, "fat_100g": 8],
        ])
        #expect(p.kcal == 131.7)
        #expect(p.kcalNote != nil)
    }

    @Test func consistentKcalIsKept() {
        let p = parseOFF(["nutriments": ["energy-kcal_100g": 64, "energy-kj_100g": 268,
                                                    "proteins_100g": 11, "carbohydrates_100g": 4, "fat_100g": 0.2]])
        #expect(p.kcal == 64)
        #expect(p.kcalNote == nil)
    }

    @Test func wrongKJKeepsKcalWhenMacrosAgree() {
        let r = Nutrition.resolveKcal(kcal: 132, kj: 3200, macroKcal: 132)
        #expect(r.value == 132 && !r.corrected)
    }

    @Test func noMacrosTrustsKJ() {
        let r = Nutrition.resolveKcal(kcal: 765, kj: 551, macroKcal: nil)
        #expect(r.corrected)
        #expect(abs((r.value ?? 0) - 131.7) < 0.1)
    }

    @Test func looksOff() {
        #expect(Nutrition.kcalLooksOff(kcal: 765, macroKcal: 132))
        #expect(!Nutrition.kcalLooksOff(kcal: 110, macroKcal: 102))   // poulet : arrondis
        #expect(!Nutrition.kcalLooksOff(kcal: 240, macroKcal: 222))   // avocat : < 20 kcal
        #expect(!Nutrition.kcalLooksOff(kcal: 0, macroKcal: 0))
    }
}

struct OverTests {
    @Test func overAfterThreePercent() {
        #expect(!Nutrition.depasse(277, objectif: 273))   // +1,5 % : toléré
        #expect(!Nutrition.depasse(281, objectif: 273))   // +2,9 %
        #expect(Nutrition.depasse(282, objectif: 273))    // +3,3 %
        #expect(!Nutrition.depasse(50, objectif: 0))
        #expect(Nutrition.etatJour(kcal: 2650, objectif: 2600) == .dansLaCible)   // +1,9 %
        #expect(Nutrition.etatJour(kcal: 2530, objectif: 2600) == .dansLaCible)   // −2,7 %
        #expect(Nutrition.etatJour(kcal: 2700, objectif: 2600) == .auDela)        // +3,8 %
        #expect(Nutrition.etatJour(kcal: 2400, objectif: 2600) == .sousObjectif)
        #expect(Nutrition.etatJour(kcal: 0, objectif: 2600) == .sousObjectif)
    }
}

@MainActor
struct PieceWeightTests {
    /// HiPro pour 100 g : 60 kcal · G 4,5 · P 10 · L 0,2.
    private func hipro() -> IngredientDraft {
        var d = IngredientDraft()
        d.kcal = "60"; d.c = "4,5"; d.p = "10"; d.f = "0,2"
        return d
    }

    @Test func switchingToPieceUsesWeightTypedDigitByDigit() {
        var d = hipro()
        d.setUnit(.pc)
        #expect(d.kcal == "60")                    // poids encore inconnu : rien ne change
        for t in ["3", "30", "300"] { d.setPieceWeight(t) }
        #expect(d.kcal == "180" && d.p == "30" && d.c == "13,5" && d.f == "0,6")
    }

    @Test func backToHundredGramsRestoresValues() {
        var d = hipro()
        d.setUnit(.pc); d.setPieceWeight("300")
        d.setUnit(.g)
        #expect(d.kcal == "60" && d.p == "10")
    }

    @Test func prefilledWeightConvertsImmediately() {
        var d = hipro()
        d.pieceWeight = "300"                      // ex. prérempli au scan
        d.setUnit(.pc)
        #expect(d.kcal == "180")
    }

    @Test func changingWeightOfSavedPieceRescales() {
        var d = IngredientDraft()
        d.unit = .pc; d.pieceWeight = "300"; d.kcal = "180"; d.p = "30"
        d.setPieceWeight("330")
        #expect(d.kcal == "198" && d.p == "33")
    }

    @Test func manualEditIsKept() {
        var d = hipro()
        d.setUnit(.pc); d.setPieceWeight("300")
        d.kcal = "175"; d.valuesEdited()
        d.setUnit(.g)                               // repart de la saisie manuelle
        #expect(d.kcal == "58,33")
    }

    @Test func quantityParsing() {
        #expect(OpenFoodFacts.pieceWeight(from: "300 g") == 300)
        #expect(OpenFoodFacts.pieceWeight(from: "4 x 125 g") == 125)
        #expect(OpenFoodFacts.pieceWeight(from: "33 cl") == 330)
        #expect(OpenFoodFacts.pieceWeight(from: "1,5 L") == 1500)
        #expect(OpenFoodFacts.pieceWeight(from: "") == nil)
    }
}
