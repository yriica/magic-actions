import Foundation

/// Tunable recognition thresholds. Distances are in normalized surface units (0..1),
/// durations in seconds.
struct EngineSettings: Hashable, Sendable {
    var tapMaxDuration = 0.35
    var tapMaxTravel = 0.05
    var groupWindow = 0.09

    var swipeMinTravel = 0.16
    var swipeMaxDuration = 0.7
    var axisDominance = 1.4

    var anchorMinAge = 0.12
    var anchorMaxTravel = 0.07

    var deadZoneEdgeX = 0.03
    var deadZoneBottom = 0.05
    var deadZoneTop = 0.0

    /// Cumulative |scroll delta| during a touch above which taps/swipes are discarded.
    var scrollContaminationThreshold = 8.0
    /// Physical button click within this window after touch end also discards it.
    var clickContaminationWindow = 0.08

    var strokeDwellTime = 0.15
    var strokeDwellMaxTravel = 0.06
    /// Fraction of the surface (from the far edge) that arms stroke drawing.
    var strokeTriggerZoneFraction = 0.3
    var strokeMinLength = 0.25
    var strokeScoreThreshold = 0.78

    static let standard = EngineSettings()
}

extension EngineSettings: Codable {
    private enum CodingKeys: String, CodingKey {
        case tapMaxDuration, tapMaxTravel, groupWindow
        case swipeMinTravel, swipeMaxDuration, axisDominance
        case anchorMinAge, anchorMaxTravel
        case deadZoneEdgeX, deadZoneBottom, deadZoneTop
        case scrollContaminationThreshold, clickContaminationWindow
        case strokeDwellTime, strokeDwellMaxTravel, strokeTriggerZoneFraction
        case strokeMinLength, strokeScoreThreshold
    }

    // Tolerant decoding: missing keys fall back to defaults so old configs keep loading.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        var s = EngineSettings.standard
        s.tapMaxDuration = try c.decodeIfPresent(Double.self, forKey: .tapMaxDuration) ?? s.tapMaxDuration
        s.tapMaxTravel = try c.decodeIfPresent(Double.self, forKey: .tapMaxTravel) ?? s.tapMaxTravel
        s.groupWindow = try c.decodeIfPresent(Double.self, forKey: .groupWindow) ?? s.groupWindow
        s.swipeMinTravel = try c.decodeIfPresent(Double.self, forKey: .swipeMinTravel) ?? s.swipeMinTravel
        s.swipeMaxDuration = try c.decodeIfPresent(Double.self, forKey: .swipeMaxDuration) ?? s.swipeMaxDuration
        s.axisDominance = try c.decodeIfPresent(Double.self, forKey: .axisDominance) ?? s.axisDominance
        s.anchorMinAge = try c.decodeIfPresent(Double.self, forKey: .anchorMinAge) ?? s.anchorMinAge
        s.anchorMaxTravel = try c.decodeIfPresent(Double.self, forKey: .anchorMaxTravel) ?? s.anchorMaxTravel
        s.deadZoneEdgeX = try c.decodeIfPresent(Double.self, forKey: .deadZoneEdgeX) ?? s.deadZoneEdgeX
        s.deadZoneBottom = try c.decodeIfPresent(Double.self, forKey: .deadZoneBottom) ?? s.deadZoneBottom
        s.deadZoneTop = try c.decodeIfPresent(Double.self, forKey: .deadZoneTop) ?? s.deadZoneTop
        s.scrollContaminationThreshold = try c.decodeIfPresent(Double.self, forKey: .scrollContaminationThreshold) ?? s.scrollContaminationThreshold
        s.clickContaminationWindow = try c.decodeIfPresent(Double.self, forKey: .clickContaminationWindow) ?? s.clickContaminationWindow
        s.strokeDwellTime = try c.decodeIfPresent(Double.self, forKey: .strokeDwellTime) ?? s.strokeDwellTime
        s.strokeDwellMaxTravel = try c.decodeIfPresent(Double.self, forKey: .strokeDwellMaxTravel) ?? s.strokeDwellMaxTravel
        s.strokeTriggerZoneFraction = try c.decodeIfPresent(Double.self, forKey: .strokeTriggerZoneFraction) ?? s.strokeTriggerZoneFraction
        s.strokeMinLength = try c.decodeIfPresent(Double.self, forKey: .strokeMinLength) ?? s.strokeMinLength
        s.strokeScoreThreshold = try c.decodeIfPresent(Double.self, forKey: .strokeScoreThreshold) ?? s.strokeScoreThreshold
        self = s
    }
}
