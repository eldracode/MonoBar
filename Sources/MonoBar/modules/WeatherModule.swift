import CoreLocation
import Foundation

@MainActor
extension BarModel {
    var weatherEnabled: Bool {
        config.weatherProvider == "openweather" && !config.weatherAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func updateWeatherLocation(_ location: CLLocationCoordinate2D) {
        weatherLocation = location
        refreshWeather(force: true)
    }

    func weatherLocationUnavailable(_ reason: String) {
        weatherSymbolName = "location.slash"
        weatherText = reason
        notifyChange()
    }

    func refreshWeather(force: Bool = false) {
        guard weatherEnabled,
              force || Date().timeIntervalSince(lastWeatherAttempt) >= config.weatherRefreshMinutes * 60 else { return }
        let coordinates: CLLocationCoordinate2D
        if let latitude = config.weatherLatitude, let longitude = config.weatherLongitude {
            coordinates = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        } else if let weatherLocation {
            coordinates = weatherLocation
        } else {
            return
        }

        let units = config.weatherUnits
        var components = URLComponents(string: "https://api.openweathermap.org/data/2.5/weather")!
        components.queryItems = [
            URLQueryItem(name: "lat", value: String(coordinates.latitude)),
            URLQueryItem(name: "lon", value: String(coordinates.longitude)),
            URLQueryItem(name: "appid", value: config.weatherAPIKey),
            URLQueryItem(name: "units", value: units)
        ]
        guard let url = components.url else { return }
        lastWeatherAttempt = Date()
        weatherRequest?.cancel()
        weatherRequest = URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            if let urlError = error as? URLError, urlError.code == .cancelled { return }
            if error != nil {
                Task { @MainActor [weak self] in self?.setWeatherStatus("Offline") }
                return
            }
            guard let response = response as? HTTPURLResponse else {
                Task { @MainActor [weak self] in self?.setWeatherStatus("No response") }
                return
            }
            guard response.statusCode == 200 else {
                let message: String
                switch response.statusCode {
                case 401: message = "API key error"
                case 404: message = "City not found"
                case 429: message = "Rate limited"
                default: message = "API \(response.statusCode)"
                }
                Task { @MainActor [weak self] in self?.setWeatherStatus(message) }
                return
            }
            guard let data,
                  let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let main = payload["main"] as? [String: Any],
                  let temperature = (main["temp"] as? NSNumber)?.doubleValue,
                  let condition = (payload["weather"] as? [[String: Any]])?.first,
                  let code = (condition["id"] as? NSNumber)?.intValue else {
                Task { @MainActor [weak self] in self?.setWeatherStatus("Bad response") }
                return
            }
            let icon = condition["icon"] as? String ?? ""
            let symbolName = Self.weatherSymbol(code: code, icon: icon)
            let unit = units == "metric" ? "°C" : (units == "imperial" ? "°F" : " K")
            let summary = "\(Int(temperature.rounded()))\(unit)"
            Task { @MainActor [weak self] in
                self?.weatherText = summary
                self?.weatherSymbolName = symbolName
                self?.weatherRequest = nil
                self?.notifyChange()
            }
        }
        weatherRequest?.resume()
    }

    func setWeatherStatus(_ status: String) {
        weatherSymbolName = "exclamationmark.triangle.fill"
        weatherText = status
        weatherRequest = nil
        notifyChange()
    }

    nonisolated private static func weatherSymbol(code: Int, icon: String) -> String {
        switch code {
        case 200..<300: return "cloud.bolt.rain.fill"
        case 300..<400: return "cloud.drizzle.fill"
        case 500..<600: return "cloud.rain.fill"
        case 600..<700: return "snowflake"
        case 700..<800: return "cloud.fog.fill"
        case 800: return icon.hasSuffix("n") ? "moon.fill" : "sun.max.fill"
        case 801: return icon.hasSuffix("n") ? "cloud.moon.fill" : "cloud.sun.fill"
        default: return "cloud.fill"
        }
    }

    var needsWeatherLocation: Bool {
        weatherEnabled && (config.weatherLatitude == nil || config.weatherLongitude == nil)
    }

    func weatherValues() -> [ModuleValue] {
        [ModuleValue(text: "", spacingAfter: 3, symbolName: weatherSymbolName), ModuleValue(text: weatherText)]
    }
}
