import Foundation

struct VietnameseLunarDate: Equatable {
    let day: Int
    let month: Int
    let year: Int
    let isLeapMonth: Bool

    var gridLabel: String {
        day == 1 ? "\(isLeapMonth ? "L" : "")\(month)/1" : String(day)
    }

    var description: String {
        let monthDescription = isLeapMonth ? "tháng \(month) nhuận" : "tháng \(month)"
        return "Ngày \(day) · \(monthDescription) âm lịch · \(yearName)"
    }

    private var yearName: String {
        let stems = ["Giáp", "Ất", "Bính", "Đinh", "Mậu", "Kỷ", "Canh", "Tân", "Nhâm", "Quý"]
        let branches = ["Tý", "Sửu", "Dần", "Mão", "Thìn", "Tỵ", "Ngọ", "Mùi", "Thân", "Dậu", "Tuất", "Hợi"]
        return "\(stems[(year + 6) % stems.count]) \(branches[(year + 8) % branches.count])"
    }
}

enum VietnameseLunarCalendar {
    private static let timeZone = 7.0
    private static let newMoonEpoch = 2_415_021.076_998_695
    private static let synodicMonth = 29.530_588_853

    static func date(for date: Date, calendar: Calendar = .autoupdatingCurrent) -> VietnameseLunarDate? {
        let components = calendar.dateComponents([.day, .month, .year], from: date)
        guard let day = components.day, let month = components.month, let year = components.year else {
            return nil
        }
        return VietnameseLunarCalendar.date(day: day, month: month, year: year)
    }

    static func date(day: Int, month: Int, year: Int) -> VietnameseLunarDate? {
        guard (1...12).contains(month), (1...31).contains(day) else { return nil }

        let dayNumber = julianDay(day: day, month: month, year: year)
        let monthStart = lunarMonthStart(for: dayNumber)
        var month11 = lunarMonth11(for: year)
        var nextMonth11 = month11
        var lunarYear: Int

        if month11 >= monthStart {
            lunarYear = year
            month11 = lunarMonth11(for: year - 1)
        } else {
            lunarYear = year + 1
            nextMonth11 = lunarMonth11(for: year + 1)
        }

        let lunarDay = dayNumber - monthStart + 1
        let monthDifference = (monthStart - month11) / 29
        var lunarMonth = monthDifference + 11
        var isLeapMonth = false

        if nextMonth11 - month11 > 365 {
            let leapMonthDifference = leapMonthOffset(from: month11)
            if monthDifference >= leapMonthDifference {
                lunarMonth = monthDifference + 10
                isLeapMonth = monthDifference == leapMonthDifference
            }
        }

        if lunarMonth > 12 {
            lunarMonth -= 12
        }
        if lunarMonth >= 11 && monthDifference < 4 {
            lunarYear -= 1
        }

        return VietnameseLunarDate(
            day: lunarDay,
            month: lunarMonth,
            year: lunarYear,
            isLeapMonth: isLeapMonth
        )
    }

    private static func lunarMonthStart(for dayNumber: Int) -> Int {
        let monthIndex = Int(floor((Double(dayNumber) - newMoonEpoch) / synodicMonth))
        let followingNewMoon = newMoonDay(monthIndex + 1)
        return followingNewMoon > dayNumber ? newMoonDay(monthIndex) : followingNewMoon
    }

    private static func lunarMonth11(for year: Int) -> Int {
        let offset = julianDay(day: 31, month: 12, year: year) - 2_415_021
        let monthIndex = Int(floor(Double(offset) / synodicMonth))
        let newMoon = newMoonDay(monthIndex)
        return sunLongitude(on: newMoon) >= 9 ? newMoonDay(monthIndex - 1) : newMoon
    }

    private static func leapMonthOffset(from month11: Int) -> Int {
        let monthIndex = Int(floor(0.5 + (Double(month11) - newMoonEpoch) / synodicMonth))
        var offset = 1
        var previousLongitude = sunLongitude(on: newMoonDay(monthIndex + offset))
        var longitude = sunLongitude(on: newMoonDay(monthIndex + offset + 1))

        while longitude != previousLongitude && offset < 14 {
            previousLongitude = longitude
            offset += 1
            longitude = sunLongitude(on: newMoonDay(monthIndex + offset + 1))
        }
        return offset
    }

    private static func julianDay(day: Int, month: Int, year: Int) -> Int {
        let adjustment = (14 - month) / 12
        let adjustedYear = year + 4_800 - adjustment
        let adjustedMonth = month + 12 * adjustment - 3
        return day + (153 * adjustedMonth + 2) / 5 + 365 * adjustedYear + adjustedYear / 4
            - adjustedYear / 100 + adjustedYear / 400 - 32_045
    }

    private static func newMoonDay(_ monthIndex: Int) -> Int {
        let time = Double(monthIndex) / 1_236.85
        let timeSquared = time * time
        let timeCubed = timeSquared * time
        let radians = Double.pi / 180
        var julianDate = 2_415_020.759_33 + 29.530_588_68 * Double(monthIndex)
            + 0.000_117_8 * timeSquared - 0.000_000_155 * timeCubed
        julianDate += 0.000_33 * sin((166.56 + 132.87 * time - 0.009_173 * timeSquared) * radians)

        let meanAnomaly = 359.2242 + 29.105_356_08 * Double(monthIndex)
            - 0.000_033_3 * timeSquared - 0.000_003_47 * timeCubed
        let moonAnomaly = 306.0253 + 385.816_918_06 * Double(monthIndex)
            + 0.010_730_6 * timeSquared + 0.000_012_36 * timeCubed
        let argumentOfLatitude = 21.2964 + 390.670_506_46 * Double(monthIndex)
            - 0.001_652_8 * timeSquared - 0.000_002_39 * timeCubed

        let correction = (0.1734 - 0.000_393 * time) * sin(meanAnomaly * radians)
            + 0.0021 * sin(2 * meanAnomaly * radians)
            - 0.4068 * sin(moonAnomaly * radians)
            + 0.0161 * sin(2 * moonAnomaly * radians)
            - 0.0004 * sin(3 * moonAnomaly * radians)
            + 0.0104 * sin(2 * argumentOfLatitude * radians)
            - 0.0051 * sin((meanAnomaly + moonAnomaly) * radians)
            - 0.0074 * sin((meanAnomaly - moonAnomaly) * radians)
            + 0.0004 * sin((2 * argumentOfLatitude + meanAnomaly) * radians)
            - 0.0004 * sin((2 * argumentOfLatitude - meanAnomaly) * radians)
            - 0.0006 * sin((2 * argumentOfLatitude + moonAnomaly) * radians)
            + 0.0010 * sin((2 * argumentOfLatitude - moonAnomaly) * radians)
            + 0.0005 * sin((2 * moonAnomaly + meanAnomaly) * radians)
        julianDate += correction

        let deltaTime: Double
        if time < -11 {
            deltaTime = 0.001 + 0.000_839 * time + 0.000_226_1 * timeSquared
                - 0.000_008_45 * timeCubed - 0.000_000_081 * time * timeCubed
        } else {
            deltaTime = -0.000_278 + 0.000_265 * time + 0.000_262 * timeSquared
        }
        return Int(floor(julianDate - deltaTime + 0.5 + timeZone / 24))
    }

    private static func sunLongitude(on julianDay: Int) -> Int {
        let time = (Double(julianDay) - 2_451_545.5 - timeZone / 24) / 36_525
        let timeSquared = time * time
        let radians = Double.pi / 180
        let meanAnomaly = 357.529_10 + 35_999.050_30 * time - 0.000_155_9 * timeSquared
            - 0.000_000_48 * time * timeSquared
        let meanLongitude = 280.466_45 + 36_000.769_83 * time + 0.000_303_2 * timeSquared
        let longitudeCorrection = (1.914_600 - 0.004_817 * time - 0.000_014 * timeSquared)
            * sin(meanAnomaly * radians)
            + (0.019_993 - 0.000_101 * time) * sin(2 * meanAnomaly * radians)
            + 0.000_290 * sin(3 * meanAnomaly * radians)
        let longitude = (meanLongitude + longitudeCorrection) * radians
        let normalizedLongitude = longitude - 2 * Double.pi * floor(longitude / (2 * Double.pi))
        return Int(floor(normalizedLongitude / Double.pi * 6))
    }
}
