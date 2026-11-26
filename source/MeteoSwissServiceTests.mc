using Toybox.Lang;
using Toybox.System;
using Toybox.Test;
using Toybox.Time;
using Toybox.Time.Gregorian;

// Simulator-only checks. Garmin removes :test functions from device builds.
(:test)
function testHourlyCompaction(logger as Test.Logger) as Lang.Boolean {
    var forecast = [{"date" => "2026-11-16"}, {"date" => "2026-11-17"}];
    var data = {
        "hourly" => {
            "time" => ["2026-11-16T09:00", "2026-11-16T12:00", "2026-11-17T00:00"],
            "temperature_2m" => [8.4, 11.8, 4.1],
            "precipitation_probability" => [15, 20, 55],
            "wind_speed_10m" => [12.1, 17.2, 19.3],
            "weather_code" => [2, 2, 61]
        }
    };
    var days = new MeteoSwissService(null).compactHourly(data, forecast);
    Test.assertMessage(days != null, "hourly series should parse");
    Test.assertEqual(2, days.size());
    Test.assertEqual(2, days[0].size());
    Test.assertEqual(1, days[1].size());
    Test.assertEqual(9, days[0][0][0]);
    Test.assertEqual(61, days[1][0][4]);
    return true;
}

(:test)
function testValidDailyResponse(logger as Test.Logger) as Lang.Boolean {
    var data = {
        "daily" => {
            "time" => ["2026-11-16", "2026-11-17", "2026-11-18"],
            "temperature_2m_max" => [12.0, 10.0, 9.0],
            "temperature_2m_min" => [4.0, 3.0, 2.0],
            "precipitation_probability_max" => [20, 45, 10],
            "wind_speed_10m_max" => [18.0, 20.0, 16.0],
            "weather_code" => [2, 61, 0]
        }
    };
    Test.assertMessage(new MeteoSwissService(null).isValidResponse(data),
                       "valid daily dates should parse");
    return true;
}

(:test)
function testMalformedHourlyIsOptional(logger as Test.Logger) as Lang.Boolean {
    var forecast = [{"date" => "2026-11-16"}];
    var data = {
        "hourly" => {
            "time" => ["2026-11-16T09:00", "2026-11-16T12:00"],
            "temperature_2m" => [8.4],
            "precipitation_probability" => [15, 20],
            "wind_speed_10m" => [12.1, 17.2],
            "weather_code" => [2, 2]
        }
    };
    Test.assert(new MeteoSwissService(null).compactHourly(data, forecast) == null);
    return true;
}

(:test)
function testHourlyPagesContinueAcrossMidnight(logger as Test.Logger) as Lang.Boolean {
    var service = new MeteoSwissService(null);
    service.weather = {"forecast" => [
        {"date" => "2030-01-01"},
        {"date" => "2030-01-02"},
        {"date" => "2030-01-03"}
    ]};
    service.hourlyDays = [
        [[0], [1], [2], [3], [4], [5], [6]],
        [[0], [1]],
        [[0]]
    ];
    var view = new MeteoSwissHourlyView(service, 0, []);
    view.nextPage();
    Test.assertEqual(0, view.dayIndex);
    Test.assertEqual(1, view.page);
    view.nextPage();
    Test.assertEqual(1, view.dayIndex);
    Test.assertEqual(0, view.page);
    view.nextPage();
    Test.assertEqual(2, view.dayIndex);
    view.nextPage();
    Test.assertEqual(2, view.dayIndex);
    view.previousPage();
    Test.assertEqual(1, view.dayIndex);
    view.previousPage();
    Test.assertEqual(0, view.dayIndex);
    Test.assertEqual(1, view.page);

    var fromTuesday = new MeteoSwissHourlyView(service, 1, []);
    fromTuesday.previousPage();
    Test.assertEqual(1, fromTuesday.dayIndex);
    return true;
}

(:test)
function testPastHoursAdvanceToTomorrow(logger as Test.Logger) as Lang.Boolean {
    var service = new MeteoSwissService(null);
    var view = new MeteoSwissHourlyView(service, 0, []);
    service.weather = {"forecast" => [
        {"date" => view.todayKey()},
        {"date" => "2030-01-02"}
    ]};
    var pastHours = [];
    for (var hour = 0; hour < System.getClockTime().hour; hour += 1) {
        pastHours.add([hour]);
    }
    service.hourlyDays = [pastHours, [[0]]];
    view.advancePastEmptyDay();
    Test.assertEqual(1, view.dayIndex);
    return true;
}

(:test)
function testSavedLocationFetchesBeforeGps(logger as Test.Logger) as Lang.Boolean {
    var service = new MeteoSwissService(null);
    service.latitude = 47.3769;
    service.longitude = 8.5417;
    service.lastLocationFix = service.now() - service.LOCATION_INTERVAL_SECONDS - 1;
    Test.assertEqual(service.REFRESH_WEATHER, service.refreshAction()); // Saved coordinates win.

    var today = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
    var date = today.year.format("%04d") + "-" +
               today.month.format("%02d") + "-" + today.day.format("%02d");
    service.weather = {
        "forecast" => [{"date" => date, "weatherCode" => 0}],
        "hourlyAvailable" => true
    };
    service.lastFetch = service.now();
    Test.assertEqual(service.REFRESH_LOCATION, service.refreshAction()); // Then update location.

    service.lastLocationAttempt = service.now();
    Test.assertEqual(service.REFRESH_NONE, service.refreshAction()); // Throttle failed GPS.
    service.lastLocationAttempt = null;

    service.locationInFlight = true;
    Test.assertEqual(service.REFRESH_NONE, service.refreshAction()); // Only one GPS attempt.
    service.locationInFlight = false;
    service.latitude = null;
    service.longitude = null;
    Test.assertEqual(service.REFRESH_LOCATION, service.refreshAction()); // First use needs GPS.
    return true;
}
