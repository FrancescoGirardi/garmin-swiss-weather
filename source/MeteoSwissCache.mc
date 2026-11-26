using Toybox.Application;
using Toybox.Lang;

// Shared by the full app and the low-memory glance. The glance only reads.
(:glance)
class MeteoSwissCache {
    const KEY = "weatherCacheDailyV1";
    const VERSION = 2;
    const HOURLY_KEY = "weatherCacheHourlyV1";
    const HOURLY_VERSION = 1;

    function read() {
        var stored = Application.Storage.getValue(KEY);
        if (stored == null) { return null; }
        var cache = stored as Lang.Dictionary;
        if (cache == null || cache["version"] != VERSION ||
            !cache.hasKey("weather") || !cache.hasKey("latitude") ||
            !cache.hasKey("longitude") || !cache.hasKey("lastFetch") ||
            !cache.hasKey("lastLocationFix")) {
            return null;
        }
        var weather = cache["weather"] as Lang.Dictionary;
        if (weather == null || !weather.hasKey("forecast") ||
            weather["forecast"] == null || weather["forecast"].size() == 0) {
            return null;
        }
        return cache;
    }

    function write(weather, latitude, longitude, lastFetch, lastLocationFix, lastLocationAttempt) {
        try {
            Application.Storage.setValue(KEY, {
                "version" => VERSION,
                "weather" => weather,
                "latitude" => latitude,
                "longitude" => longitude,
                "lastFetch" => lastFetch,
                "lastLocationFix" => lastLocationFix,
                "lastLocationAttempt" => lastLocationAttempt
            });
        } catch (ex) {
            // Weather stays visible for this session even if storage is full.
        }
    }

    // The glance reads only KEY. Keeping 72 hourly points under a separate
    // value avoids deserializing them in Garmin's restricted glance runtime.
    function readHourly(lastFetch) {
        if (lastFetch == null) { return null; }
        var stored = Application.Storage.getValue(HOURLY_KEY) as Lang.Dictionary;
        if (stored == null || !stored.hasKey("version") ||
            !stored.hasKey("lastFetch") || !stored.hasKey("days") ||
            stored["version"] != HOURLY_VERSION ||
            stored["lastFetch"] != lastFetch || stored["days"] == null) {
            return null;
        }
        return stored["days"];
    }

    function writeHourly(days, lastFetch) {
        if (days == null) { return false; }
        try {
            Application.Storage.setValue(HOURLY_KEY, {
                "version" => HOURLY_VERSION,
                "lastFetch" => lastFetch,
                "days" => days
            });
            return true;
        } catch (ex) {
            // The full forecast remains useful if this optional cache is full.
            return false;
        }
    }
}
