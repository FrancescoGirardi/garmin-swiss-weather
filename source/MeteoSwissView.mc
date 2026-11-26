using Toybox.Graphics;
using Toybox.Lang;
using Toybox.System;
using Toybox.Time;
using Toybox.Time.Gregorian;
using Toybox.Timer;
using Toybox.WatchUi;

class MeteoSwissView extends WatchUi.View {
    // Fixed 454px round AMOLED canvas. Content stays inside the safe circle.
    const INK = 0xF1F8FB;
    const MUTED = 0xA3BAC6;
    const QUIET = 0x7894A3;
    const ACCENT = 0x78D7EF;
    const RULE = 0x244558;
    const NAVY = 0x04131F;
    const SEA = 0x071D2D;
    const SEA_DEEP = 0x092538;
    const LEFT = 72;
    const LABEL_LEFT = 116;
    const RIGHT = 382;
    const ROW_TOP = 204;
    const ROW_HEIGHT = 60;

    var service;
    var minuteTimer;
    var shownDate;
    var labelFont;
    var detailFont;
    var dateFont;
    var valueFont;
    var clockFont;
    var freshnessFont;
    var hintFont;
    var weatherIcons;
    var selectedDay = -1;
    var detailOpen = false;
    var detailDayIndex;

    function initialize() {
        View.initialize();
        service = new MeteoSwissService(method(:weatherChanged));
        labelFont = Graphics.getVectorFont({:face => "RobotoRegular", :size => 18});
        detailFont = Graphics.getVectorFont({:face => "RobotoRegular", :size => 16});
        dateFont = Graphics.getVectorFont({:face => "RobotoRegular", :size => 21});
        valueFont = Graphics.getVectorFont({:face => "RobotoCondensedBold", :size => 36});
        clockFont = Graphics.getVectorFont({:face => "RobotoCondensedRegular", :size => 76});
        freshnessFont = Graphics.getVectorFont({:face => "RobotoRegular", :size => 14});
        hintFont = Graphics.getVectorFont({:face => "RobotoRegular", :size => 12});
        weatherIcons = [
            WatchUi.loadResource(Rez.Drawables.WeatherSun),
            WatchUi.loadResource(Rez.Drawables.WeatherPartCloud),
            WatchUi.loadResource(Rez.Drawables.WeatherCloud),
            WatchUi.loadResource(Rez.Drawables.WeatherRain),
            WatchUi.loadResource(Rez.Drawables.WeatherSnow),
            WatchUi.loadResource(Rez.Drawables.WeatherStorm),
            WatchUi.loadResource(Rez.Drawables.WeatherFog),
            WatchUi.loadResource(Rez.Drawables.WeatherUnknown)
        ];
    }

    function onShow() {
        detailOpen = false;
        detailDayIndex = null;
        shownDate = dateKey();
        service.start();
        if (minuteTimer == null) {
            minuteTimer = new Timer.Timer();
            armMinuteTimer();
        }
    }

    function onHide() {
        // Keep the refresh timer alive while an hourly page is stacked over
        // this view; it still updates the visible page once per minute.
        if (!detailOpen && minuteTimer != null) {
            minuteTimer.stop();
            minuteTimer = null;
        }
        if (!detailOpen) { service.stop(); }
    }

    function onMinute() as Void {
        var currentDate = dateKey();
        if (!shownDate.equals(currentDate)) {
            shownDate = currentDate;
            service.start();
        } else {
            service.checkForRefresh();
        }
        if (detailOpen && detailDayIndex != null) {
            service.ensureHourlyForDay(detailDayIndex);
        }
        WatchUi.requestUpdate();
        if (minuteTimer != null) {
            armMinuteTimer();
        }
    }

    function armMinuteTimer() {
        // Wake once just after the next minute boundary, not one minute after
        // launch, so the clock is never almost a minute behind.
        var remaining = (60 - System.getClockTime().sec) * 1000 + 100;
        minuteTimer.start(method(:onMinute), remaining, false);
    }

    function weatherChanged() {
        WatchUi.requestUpdate();
    }

    function refresh() {
        service.manualRefresh();
    }

    function selectNextDay() {
        var count = forecastCount();
        if (count == 0) { return; }
        if (selectedDay < count - 1) { selectedDay += 1; }
        WatchUi.requestUpdate();
    }

    function selectPreviousDay() {
        var count = forecastCount();
        if (count == 0) { return; }
        if (selectedDay < 0) { selectedDay = count - 1; }
        else if (selectedDay > 0) { selectedDay -= 1; }
        WatchUi.requestUpdate();
    }

    function forecastCount() {
        var weather = service.getWeather();
        if (weather == null || weather["forecast"] == null) { return 0; }
        var count = weather["forecast"].size();
        return count < 3 ? count : 3;
    }

    function selectOrRefresh() {
        if (selectedDay < 0) { refresh(); }
        else { openDay(selectedDay); }
    }

    function tapAt(x, y) {
        if (x >= LEFT - 12 && x <= RIGHT + 12 &&
            y >= ROW_TOP && y < ROW_TOP + 3 * ROW_HEIGHT - 8) {
            openDay(((y - ROW_TOP) / ROW_HEIGHT).toNumber());
        }
    }

    function openDay(index) {
        var weather = service.getWeather();
        if (weather == null || weather["forecast"] == null ||
            index < 0 || index >= weather["forecast"].size()) { return; }
        var detail = new MeteoSwissHourlyView(service, index, weatherIcons);
        detailOpen = true;
        detailDayIndex = index;
        WatchUi.pushView(detail, new MeteoSwissHourlyInputDelegate(detail), WatchUi.SLIDE_LEFT);
    }

    function onUpdate(dc) {
        var width = dc.getWidth();
        drawBackground(dc, width);
        drawHeadingMarker(dc, width);
        drawClock(dc, width);
        drawCalendar(dc, width);

        var weather = service.getWeather();
        if (weather == null || weather["forecast"] == null || weather["forecast"].size() == 0) {
            dc.setColor(MUTED, Graphics.COLOR_TRANSPARENT);
            dc.drawText(width / 2, 263, dateFont,
                        service.getStatus(), Graphics.TEXT_JUSTIFY_CENTER);
        } else {
            drawForecast(dc, weather["forecast"]);
        }
        drawFreshness(dc, width);
        drawBattery(dc, width);
    }

    function drawBackground(dc, width) {
        // Three dark tones suggest depth without a bitmap or per-pixel gradient.
        dc.setColor(NAVY, NAVY);
        dc.clear();
        dc.setColor(SEA, SEA);
        dc.fillCircle(width / 2, 515, 350);
        dc.setColor(SEA_DEEP, SEA_DEEP);
        dc.fillCircle(width / 2, 540, 300);
    }

    function drawHeadingMarker(dc, width) {
        dc.setColor(RULE, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(width / 2 - 29, 43, width / 2 - 8, 43);
        dc.drawLine(width / 2 + 8, 43, width / 2 + 29, 43);
        dc.setColor(ACCENT, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(width / 2, 43, 2);
    }

    function drawBattery(dc, width) {
        var battery = System.getSystemStats().battery;
        var text = battery.format("%.0f") + "%";
        var groupWidth = 29 + dc.getTextWidthInPixels(text, detailFont);
        var x = (width - groupWidth) / 2;
        var fill = (battery * 16 / 100).toNumber();
        dc.setColor(MUTED, Graphics.COLOR_TRANSPARENT);
        dc.drawRectangle(x, 411, 21, 11);
        dc.fillRectangle(x + 22, 414, 2, 5);
        if (fill > 0) {
            dc.setColor(ACCENT, Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(x + 2, 413, fill, 7);
        }
        dc.setColor(MUTED, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x + 29, 406, detailFont, text, Graphics.TEXT_JUSTIFY_LEFT);
    }

    function drawFreshness(dc, width) {
        if (service.isRefreshing()) {
            dc.setColor(ACCENT, Graphics.COLOR_TRANSPARENT);
            dc.drawText(width / 2, 383, freshnessFont,
                        service.getStatus(), Graphics.TEXT_JUSTIFY_CENTER);
            return;
        }
        var lastFetch = service.getLastFetch();
        if (lastFetch == null) { return; }
        var age = Time.now().value() - lastFetch;
        if (age < 0) { age = 0; }
        var ageText = "now";
        if (age >= 86400) {
            ageText = (age / 86400).format("%.0f") + "d ago";
        } else if (age >= 3600) {
            ageText = (age / 3600).format("%.0f") + "h ago";
        } else if (age >= 60) {
            ageText = (age / 60).format("%.0f") + "m ago";
        }
        var prefix = service.isUsingCachedData() ? "Cached" : "Updated";
        dc.setColor(QUIET, Graphics.COLOR_TRANSPARENT);
        dc.drawText(width / 2, 383, freshnessFont,
                    prefix + " " + ageText, Graphics.TEXT_JUSTIFY_CENTER);
    }

    function drawClock(dc, width) {
        var clock = System.getClockTime();
        var hour = clock.hour;
        var suffix = "";
        if (!System.getDeviceSettings().is24Hour) {
            suffix = hour < 12 ? "AM" : "PM";
            hour = hour % 12;
            if (hour == 0) {
                hour = 12;
            }
        }
        var timeText = hour.format("%02d") + ":" + clock.min.format("%02d");
        dc.setColor(INK, Graphics.COLOR_TRANSPARENT);
        dc.drawText(width / 2, 65, clockFont,
                    timeText, Graphics.TEXT_JUSTIFY_CENTER);
        if (!suffix.equals("")) {
            dc.setColor(MUTED, Graphics.COLOR_TRANSPARENT);
            dc.drawText(width / 2 + dc.getTextWidthInPixels(timeText, clockFont) / 2 + 7,
                        117, detailFont, suffix, Graphics.TEXT_JUSTIFY_LEFT);
        }
    }

    function drawCalendar(dc, width) {
        var today = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
        var weekdays = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"];
        var months = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN",
                      "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"];
        var dateText = weekdays[today.day_of_week - 1] + "  " +
                       today.day.format("%02d") + " " + months[today.month - 1];
        dc.setColor(MUTED, Graphics.COLOR_TRANSPARENT);
        dc.drawText(width / 2, 149, dateFont, dateText, Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(RULE, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(LEFT, 183, RIGHT, 183);
    }

    function drawForecast(dc, forecast) {
        dc.setColor(QUIET, Graphics.COLOR_TRANSPARENT);
        dc.drawText(227, 185, hintFont,
                    "TAP A DAY FOR HOURLY", Graphics.TEXT_JUSTIFY_CENTER);
        for (var i = 0; i < forecast.size() && i < 3; i += 1) {
            var item = forecast[i];
            var y = ROW_TOP + i * ROW_HEIGHT;
            if (i == selectedDay) {
                dc.setColor(SEA_DEEP, SEA_DEEP);
                dc.fillRectangle(LEFT - 8, y - 2, RIGHT - LEFT + 16, 54);
            }
            var label = weekdayLabel(item["date"]);
            var weatherCode = item.hasKey("weatherCode") ? item["weatherCode"] : null;
            dc.drawBitmap(LEFT, y + 7,
                          weatherIcons[MeteoSwissConditions.iconIndex(weatherCode)]);
            // Separate horizontal lanes keep values clear, including 100% rain.
            dc.setColor(i == 0 ? ACCENT : MUTED, Graphics.COLOR_TRANSPARENT);
            dc.drawText(LABEL_LEFT, y, labelFont, label, Graphics.TEXT_JUSTIFY_LEFT);
            dc.setColor(QUIET, Graphics.COLOR_TRANSPARENT);
            dc.drawText(LABEL_LEFT, y + 23, detailFont,
                        shortDate(item["date"]), Graphics.TEXT_JUSTIFY_LEFT);
            dc.setColor(INK, Graphics.COLOR_TRANSPARENT);
            dc.drawText(232, y - 3, valueFont,
                        formatNumber(item["highTemp"]) + "°", Graphics.TEXT_JUSTIFY_RIGHT);
            dc.setColor(MUTED, Graphics.COLOR_TRANSPARENT);
            dc.drawText(243, y + 9, labelFont,
                        formatNumber(item["lowTemp"]) + "°", Graphics.TEXT_JUSTIFY_LEFT);
            dc.setColor(ACCENT, Graphics.COLOR_TRANSPARENT);
            dc.drawText(RIGHT, y + 1, dateFont,
                        formatNumber(item["precipProbability"]) + "%", Graphics.TEXT_JUSTIFY_RIGHT);
            dc.setColor(MUTED, Graphics.COLOR_TRANSPARENT);
            dc.drawText(RIGHT, y + 27, detailFont,
                        formatNumber(item["windSpeed"]) + " km/h", Graphics.TEXT_JUSTIFY_RIGHT);
            if (i < 2) {
                dc.setColor(RULE, Graphics.COLOR_TRANSPARENT);
                dc.drawLine(LEFT, y + 52, RIGHT, y + 52);
            }
        }
    }

    function shortDate(value) {
        if (value == null || value.length() < 10) {
            return "";
        }
        return value.substring(8, 10) + "." + value.substring(5, 7);
    }

    function weekdayLabel(value) {
        if (value == null || value.length() < 10) {
            return "---";
        }
        // The API date is local to the forecast position. Noon UTC keeps the
        // calendar day stable when Gregorian.info applies the watch timezone.
        var day = Gregorian.moment({
            :year => value.substring(0, 4).toNumber(),
            :month => value.substring(5, 7).toNumber(),
            :day => value.substring(8, 10).toNumber(),
            :hour => 12
        });
        var names = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"];
        return names[Gregorian.info(day, Time.FORMAT_SHORT).day_of_week - 1];
    }

    function dateKey() {
        var today = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
        return today.year.format("%04d") + "-" +
               today.month.format("%02d") + "-" + today.day.format("%02d");
    }

    function formatNumber(value) {
        if (value == null) {
            return "--";
        }
        return value.format("%.0f");
    }
}
