import SwiftUI

final class AppSettings: ObservableObject {
    @AppStorage("isDarkMode") var isDarkMode: Bool = true {
        didSet { objectWillChange.send() }
    }
    @AppStorage("language") var language: String = "en" { // en, es, fr
        didSet { objectWillChange.send() }
    }
    @AppStorage("reputationScore") var reputationScore: Int = 0 {
        didSet { objectWillChange.send() }
    }

    func localized(_ key: LocalizedKey) -> String {
        switch language {
        case "es": return key.es
        case "fr": return key.fr
        default: return key.en
        }
    }
}

struct LocalizedKey {
    let en: String
    let es: String
    let fr: String

    static let searchPlaceholder = LocalizedKey(en: "Search address or place", es: "Buscar dirección o lugar", fr: "Rechercher une adresse ou un lieu")
    static let nearbyPlaces = LocalizedKey(en: "Nearby Places", es: "Lugares cercanos", fr: "Lieux à proximité")
    static let tapCategory = LocalizedKey(en: "Tap a category to load animated markers near you.", es: "Toque una categoría para cargar marcadores animados cerca de usted.", fr: "Touchez une catégorie pour charger des marqueurs animés près de vous.")
    static let directions = LocalizedKey(en: "Directions", es: "Indicaciones", fr: "Itinéraire")
    static let collapse = LocalizedKey(en: "Collapse", es: "Contraer", fr: "Réduire")
    static let expand = LocalizedKey(en: "Expand", es: "Étendre", fr: "Développer")
    static let mapTab = LocalizedKey(en: "Map", es: "Mapa", fr: "Carte")
    static let reportsTab = LocalizedKey(en: "Reports", es: "Reportes", fr: "Signalements")
    static let settingsTab = LocalizedKey(en: "Settings", es: "Ajustes", fr: "Réglages")
    static let darkMode = LocalizedKey(en: "Dark Mode", es: "Modo oscuro", fr: "Mode sombre")
    static let language = LocalizedKey(en: "Language", es: "Idioma", fr: "Langue")
    static let trafficReports = LocalizedKey(en: "Traffic Reports", es: "Reportes de tráfico", fr: "Signalements de trafic")
    static let submitReport = LocalizedKey(en: "Submit Report", es: "Enviar reporte", fr: "Envoyer un signalement")
    static let confirmStillThere = LocalizedKey(en: "Still there?", es: "¿Sigue allí?", fr: "Toujours là ?")
    static let yes = LocalizedKey(en: "Yes", es: "Sí", fr: "Oui")
    static let no = LocalizedKey(en: "No", es: "No", fr: "Non")
    static let eta = LocalizedKey(en: "ETA", es: "ETA", fr: "ETA")
}

