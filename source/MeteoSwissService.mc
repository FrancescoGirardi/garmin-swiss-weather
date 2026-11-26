using Toybox.Application;
using Toybox.Communications;
using Toybox.Lang;
using Toybox.Position;
using Toybox.Time;
using Toybox.Time.Gregorian;
using Toybox.Timer;

class MeteoSwissService {
    // Provider-specific values stay together. A different data source would
    // also need response mapping below and weather-code mapping in Conditions.
    const API_URL = "https://api.open-meteo.com/v1/forecast";
    const API_DAILY_FIELDS = "temperature_2m_max,temperature_2m_min,precipitation_probability_max,wind_speed_10m_max,weather_code";
    const API_CURRENT_FIELDS = "temperature_2m";
    const API_HOURLY_FIELDS = "temperature_2m,precipitation_probability,wind_speed_10m,weather_code";
    // CH2 is the MeteoSwiss model with the 120-hour horizon required for
    // three full daily forecasts. CH1 only provides about 33 hours.
    const API_MODEL = "meteoswiss_icon_ch2";
    const FORECAST_DAYS = 3;

    const REFRESH_INTERVAL_SECONDS = 1800;   // 30 minutes
    const LOCATION_INTERVAL_SECONDS = 14400; // 4 hours
    const RETRY_INTERVAL_SECONDS = 300;       // 5 minutes after a failed attempt
    const BACKGROUND_LOCATION_RETRY_SECONDS = 1800; // 30 minutes
    const LOCATION_TIMEOUT_MS = 25000;
    const LOCATION_CHANGE_DEGREES = 0.05;    // approximately 5 km in Switzerland
    const REFRESH_NONE = 0;
    const REFRESH_WEATHER = 1;
    const REFRESH_LOCATION = 2;

    var changed;
    var weather;
    var hourlyDays;
    var latitude;
    var longitude;
    var lastFetch;
    var lastLocationFix;
    var lastLocationAttempt;
    var lastRequestAttempt;
    var locationTimer;
    var locationChanged = false;
    var cacheLoaded = false;
    var requestInFlight = false;
    var locationInFlight = false;
    var status = "Starting…";

    function initialize(changedCallback) {
        changed = changedCallback;
    }

    function start() {
        // Reopening the main view must not overwrite a location or request
        // that changed while its hourly detail page was visible.
        if (!cacheLoaded) {
            loadCache();
            cacheLoaded = true;
        }
        useRecentDeviceLocation();
        announceChange();

        checkForRefresh();
    }

    // A saved coordinate can refresh weather immediately. A newer GPS fix is
    // useful when the user has moved, but it must not gate the forecast.
    function checkForRefresh() {
        var action = refreshAction();
        if (action == REFRESH_WEATHER) {
            fetchWeather();
        } else if (action == REFRESH_LOCATION) {
            acquireLocation();
        } else if (weather != null && !isUsingCachedData() && !requestInFlight) {
            status = "Updated " + ageLabel(lastFetch) + " ago";
            announceChange();
        }
    }

    // Keep this decision separate from the radio calls so the priority is
    // testable without starting GPS or a network request in the simulator.
    function refreshAction() {
        if (requestInFlight || locationInFlight) { return REFRESH_NONE; }
        if (hasSavedLocation() && shouldFetch() &&
            (lastRequestAttempt == null || now() - lastRequestAttempt >= RETRY_INTERVAL_SECONDS)) {
            return REFRESH_WEATHER; // Fetch from the saved coordinate first.
        }
        var locationRetry = hasSavedLocation() ? BACKGROUND_LOCATION_RETRY_SECONDS : RETRY_INTERVAL_SECONDS;
        if (shouldAcquireLocation() &&
            (lastLocationAttempt == null || now() - lastLocationAttempt >= locationRetry)) {
            return REFRESH_LOCATION; // Optional background GPS, or first-use GPS.
        }
        return REFRESH_NONE;
    }

    function manualRefresh() {
        if (requestInFlight) { return; }
        if (hasSavedLocation()) {
            cancelLocationAttempt();
            fetchWeather();
        } else if (!locationInFlight) {
            acquireLocation();
        }
    }

    function stop() {
        cancelLocationAttempt();
    }

    function hasSavedLocation() {
        return latitude != null && longitude != null;
    }

    // Garmin may already have a recent position from another activity. Read
    // it without starting a new GPS acquisition, and reject old fixes.
    function useRecentDeviceLocation() {
        try {
            var info = Position.getInfo();
            if (info == null || info.position == null || info.when == null ||
                info.accuracy < Position.QUALITY_LAST_KNOWN) { return; }
            var fixTime = info.when.value();
            if (fixTime > now() + 300 || now() - fixTime > LOCATION_INTERVAL_SECONDS) { return; }
            if (lastLocationFix != null && fixTime < lastLocationFix) { return; }
            var degrees = info.position.toDegrees();
            var moved = !hasSavedLocation() ||
                        abs(latitude - degrees[0]) > LOCATION_CHANGE_DEGREES ||
                        abs(longitude - degrees[1]) > LOCATION_CHANGE_DEGREES;
            var newerFix = lastLocationFix == null || fixTime > lastLocationFix;
            latitude = degrees[0];
            longitude = degrees[1];
            if (newerFix) { lastLocationFix = fixTime; }
            if (moved) {
                // Keep the old forecast visible until its replacement succeeds.
                locationChanged = true;
            }
            if (weather != null && newerFix && !locationChanged) { saveCache(); }
        } catch (ex) {
            // Position.getInfo may be unavailable before the first watch fix.
        }
    }

    function cancelLocationAttempt() {
        if (locationTimer != null) {
            locationTimer.stop();
            locationTimer = null;
        }
        if (locationInFlight) {
            locationInFlight = false;
            try {
                Position.enableLocationEvents(Position.LOCATION_DISABLE, null);
            } catch (ex) {
                // The view is closing or the positioning subsystem is unavailable.
            }
        }
    }

    function onLocationTimeout() as Void {
        cancelLocationAttempt();
        if (!hasSavedLocation()) {
            status = "GPS location unavailable";
            announceChange();
        } else {
            checkForRefresh();
        }
    }

    function isRefreshing() {
        // Background GPS does not obscure a usable saved forecast.
        return requestInFlight || (locationInFlight && !hasSavedLocation());
    }

    function getWeather() {
        return weather;
    }

    function getHourlyForDay(index) {
        if (hourlyDays == null || index < 0 || index >= hourlyDays.size()) {
            return null;
        }
        return hourlyDays[index];
    }

    // A user may open a day immediately after upgrading from a daily-only
    // build. Fetch its missing detail using the saved position, without a
    // second GPS fix or an extra request if one is already in progress.
    function ensureHourlyForDay(index) {
        var rows = getHourlyForDay(index);
        if (rows != null && rows.size() > 0) { return; }
        if (requestInFlight) { return; }
        if (lastRequestAttempt != null &&
            now() - lastRequestAttempt < RETRY_INTERVAL_SECONDS) { return; }
        if (hasSavedLocation()) {
            cancelLocationAttempt();
            fetchWeather();
        } else {
            checkForRefresh();
        }
    }

    function getStatus() {
        return status;
    }

    function getLastFetch() {
        return lastFetch;
    }

    function isUsingCachedData() {
        return status.equals("Offline — cached forecast");
    }

    function loadCache() {
        var cache = new MeteoSwissCache().read();
        if (cache == null) { return; }
        weather = cache["weather"];
        latitude = cache["latitude"];
        longitude = cache["longitude"];
        lastFetch = cache["lastFetch"];
        lastLocationFix = cache["lastLocationFix"];
        lastLocationAttempt = cache.hasKey("lastLocationAttempt") ? cache["lastLocationAttempt"] : null;
        hourlyDays = new MeteoSwissCache().readHourly(lastFetch);
        locationChanged = false;
    }

    function saveCache() {
        new MeteoSwissCache().write(weather, latitude, longitude, lastFetch,
                                    lastLocationFix, lastLocationAttempt);
    }

    function shouldAcquireLocation() {
        return !hasSavedLocation() || lastLocationFix == null ||
               now() - lastLocationFix >= LOCATION_INTERVAL_SECONDS;
    }

    function shouldFetch() {
        return locationChanged || weather == null || lastFetch == null ||
               !hasWeatherCodes() ||
               !weather.hasKey("hourlyAvailable") ||
               !isForecastForToday() ||
               now() - lastFetch >= REFRESH_INTERVAL_SECONDS;
    }

    function hasWeatherCodes() {
        return weather != null && weather["forecast"] != null &&
               weather["forecast"].size() > 0 &&
               weather["forecast"][0].hasKey("weatherCode");
    }

    function isForecastForToday() {
        if (weather == null || weather["forecast"] == null ||
            weather["forecast"].size() == 0) {
            return false;
        }
        var today = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
        var key = today.year.format("%04d") + "-" +
                  today.month.format("%02d") + "-" + today.day.format("%02d");
        return weather["forecast"][0]["date"].equals(key);
    }

    function acquireLocation() {
        if (locationInFlight) { return; }
        locationInFlight = true;
        lastLocationAttempt = now();
        if (weather != null && !locationChanged) { saveCache(); }
        if (!hasSavedLocation()) {
            status = "Getting GPS location…";
            announceChange();
        }
        try {
            locationTimer = new Timer.Timer();
            locationTimer.start(method(:onLocationTimeout), LOCATION_TIMEOUT_MS, false);
            Position.enableLocationEvents(Position.LOCATION_ONE_SHOT, method(:onPosition));
        } catch (ex) {
            cancelLocationAttempt();
            if (!hasSavedLocation()) {
                status = "GPS location unavailable";
                announceChange();
            }
        }
    }

    function onPosition(info as Position.Info) as Void {
        if (!locationInFlight) { return; } // A timed-out fix arrived too late.
        cancelLocationAttempt();
        if (info == null || info.position == null || info.accuracy < Position.QUALITY_POOR ||
            (info.when != null && (info.when.value() > now() + 300 ||
                                    now() - info.when.value() > LOCATION_INTERVAL_SECONDS))) {
            if (!hasSavedLocation()) {
                status = "GPS location unavailable";
                announceChange();
            } else {
                checkForRefresh();
            }
            return;
        }

        var degrees = info.position.toDegrees();
        var previousLatitude = latitude;
        var previousLongitude = longitude;
        latitude = degrees[0];
        longitude = degrees[1];
        lastLocationFix = info.when != null ? info.when.value() : now();

        var moved = previousLatitude == null || previousLongitude == null ||
                    abs(latitude - previousLatitude) > LOCATION_CHANGE_DEGREES ||
                    abs(longitude - previousLongitude) > LOCATION_CHANGE_DEGREES;
        if (moved) { locationChanged = true; }
        if (moved) {
            fetchWeather();
        } else {
            if (weather != null && !locationChanged) { saveCache(); }
            checkForRefresh();
        }
    }

    function fetchWeather() {
        if (requestInFlight || latitude == null || longitude == null) {
            return;
        }
        requestInFlight = true;
        lastRequestAttempt = now();
        status = "Updating forecast…";
        announceChange();

        var parameters = {
            "latitude" => latitude.format("%.4f"),
            "longitude" => longitude.format("%.4f"),
            "daily" => API_DAILY_FIELDS,
            "current" => API_CURRENT_FIELDS,
            "hourly" => API_HOURLY_FIELDS,
            "forecast_days" => FORECAST_DAYS.toString(),
            "timezone" => "auto",
            "models" => API_MODEL
        };
        var options = {
            :method => Communications.HTTP_REQUEST_METHOD_GET,
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
        };
        Communications.makeWebRequest(API_URL, parameters, options, method(:onResponse));
    }

    function onResponse(responseCode as Lang.Number, data as Communications.ContentType?) as Void {
        requestInFlight = false;
        var nextWeather = null;
        var nextHourly = null;
        if (responseCode == 200) {
            try {
                var json = data as Lang.Dictionary;
                if (json != null && isValidResponse(json)) {
                    nextWeather = compactResponse(json);
                    // Hourly fields are optional; never discard valid daily
                    // data because the detailed feed changed its shape.
                    try {
                        nextHourly = compactHourly(json, nextWeather["forecast"]);
                    } catch (ex) {
                        nextHourly = null;
                    }
                }
            } catch (ex) {
                nextWeather = null;
            }
        }
        if (nextWeather == null) {
            status = weather == null ? "Forecast unavailable (" + responseCode + ")" : "Offline — cached forecast";
            announceChange();
            checkForRefresh();
            return;
        }

        weather = nextWeather;
        hourlyDays = nextHourly;
        lastFetch = now();
        locationChanged = false;
        weather["hourlyAvailable"] = new MeteoSwissCache().writeHourly(hourlyDays, lastFetch);
        status = "Updated now";
        saveCache();
        announceChange();
        checkForRefresh();
    }

    function isValidResponse(data as Lang.Dictionary) as Lang.Boolean {
        if (!data.hasKey("daily") || data["daily"] == null) {
            return false;
        }
        var daily = data["daily"] as Lang.Dictionary;
        var valid = daily != null && daily.hasKey("time") &&
               daily.hasKey("temperature_2m_max") && daily.hasKey("temperature_2m_min") &&
               daily.hasKey("precipitation_probability_max") && daily.hasKey("wind_speed_10m_max") &&
               daily.hasKey("weather_code") &&
               daily["time"] != null && daily["temperature_2m_max"] != null &&
               daily["temperature_2m_min"] != null && daily["precipitation_probability_max"] != null &&
               daily["wind_speed_10m_max"] != null && daily["weather_code"] != null &&
               daily["time"].size() > 0 &&
               daily["time"].size() == daily["temperature_2m_max"].size() &&
               daily["time"].size() == daily["temperature_2m_min"].size() &&
               daily["time"].size() == daily["precipitation_probability_max"].size() &&
               daily["time"].size() == daily["wind_speed_10m_max"].size() &&
               daily["time"].size() == daily["weather_code"].size();
        if (!valid) { return false; }
        var count = daily["time"].size();
        if (count > FORECAST_DAYS) { count = FORECAST_DAYS; }
        for (var i = 0; i < count; i += 1) {
            var date = daily["time"][i];
            if (!(date instanceof Lang.String) || date.length() < 10 ||
                !date.substring(4, 5).equals("-") || !date.substring(7, 8).equals("-")) {
                return false;
            }
        }
        return true;
    }

    function compactResponse(data as Lang.Dictionary) as Lang.Dictionary {
        var daily = data["daily"] as Lang.Dictionary;
        // Current conditions are model values. Keep them optional so a daily
        // forecast remains usable if the provider omits this field.
        var currentTemp = null;
        if (data.hasKey("current")) {
            var current = data["current"] as Lang.Dictionary;
            if (current != null && current.hasKey("temperature_2m")) {
                var value = current["temperature_2m"];
                if (value instanceof Lang.Number || value instanceof Lang.Float ||
                    value instanceof Lang.Double) {
                    currentTemp = value;
                }
            }
        }
        var forecast = [];
        var count = daily["time"].size();
        if (count > FORECAST_DAYS) {
            count = FORECAST_DAYS;
        }
        for (var i = 0; i < count; i += 1) {
            forecast.add({
                // The date is local to the forecast position because timezone=auto.
                "date" => daily["time"][i],
                "highTemp" => numericOrNull(daily["temperature_2m_max"][i]),
                "lowTemp" => numericOrNull(daily["temperature_2m_min"][i]),
                "precipProbability" => numericOrNull(daily["precipitation_probability_max"][i]),
                "windSpeed" => numericOrNull(daily["wind_speed_10m_max"][i]),
                "weatherCode" => numericOrNull(daily["weather_code"][i])
            });
        }
        return { "forecast" => forecast, "currentTemp" => currentTemp };
    }

    // Each day contains compact [hour, °C, rain %, wind km/h, WMO code]
    // records. We retain the actual hourly cadence; sparse upstream data can
    // still be shown without inventing intermediate forecasts.
    function compactHourly(data, forecast) {
        if (!data.hasKey("hourly") || data["hourly"] == null) { return null; }
        var hourly = data["hourly"] as Lang.Dictionary;
        if (hourly == null || !hourly.hasKey("time") ||
            !hourly.hasKey("temperature_2m") ||
            !hourly.hasKey("precipitation_probability") ||
            !hourly.hasKey("wind_speed_10m") || !hourly.hasKey("weather_code")) {
            return null;
        }
        var times = hourly["time"];
        var temps = hourly["temperature_2m"];
        var rains = hourly["precipitation_probability"];
        var winds = hourly["wind_speed_10m"];
        var codes = hourly["weather_code"];
        if (times == null || temps == null || rains == null || winds == null || codes == null ||
            times.size() == 0 || times.size() > 96 ||
            times.size() != temps.size() || times.size() != rains.size() ||
            times.size() != winds.size() || times.size() != codes.size()) {
            return null;
        }

        var days = [];
        for (var day = 0; day < forecast.size(); day += 1) { days.add([]); }
        var found = false;
        for (var i = 0; i < times.size(); i += 1) {
            var stamp = times[i];
            if (!(stamp instanceof Lang.String) || stamp.length() < 16 ||
                !stamp.substring(10, 11).equals("T") || !stamp.substring(13, 16).equals(":00")) {
                continue;
            }
            var hour = stamp.substring(11, 13).toNumber();
            if (hour < 0 || hour > 23) { continue; }
            for (var j = 0; j < forecast.size(); j += 1) {
                if (stamp.substring(0, 10).equals(forecast[j]["date"])) {
                    days[j].add([
                        hour, numericOrNull(temps[i]), numericOrNull(rains[i]),
                        numericOrNull(winds[i]), numericOrNull(codes[i])
                    ]);
                    found = true;
                    break;
                }
            }
        }
        return found ? days : null;
    }

    function numericOrNull(value) {
        if (value instanceof Lang.Number || value instanceof Lang.Float ||
            value instanceof Lang.Double) {
            return value;
        }
        return null;
    }

    function ageLabel(timestamp) {
        if (timestamp == null) {
            return "unknown";
        }
        var minutes = (now() - timestamp) / 60;
        if (minutes < 1) {
            return "now";
        }
        return minutes.format("%.0f") + " min";
    }

    function now() {
        return Time.now().value();
    }

    function abs(value) {
        if (value < 0) {
            return -value;
        }
        return value;
    }

    function announceChange() {
        if (changed != null) {
            changed.invoke();
        }
    }
}
