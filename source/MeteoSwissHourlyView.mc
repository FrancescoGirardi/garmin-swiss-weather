using Toybox.Graphics;
using Toybox.Lang;
using Toybox.System;
using Toybox.Time;
using Toybox.Time.Gregorian;
using Toybox.WatchUi;

// Six actual model hours per page. Paging continues into later forecast days,
// while each page stays within one date so the midnight boundary is clear.
// The view reads the service's compact data as it is refreshed.
class MeteoSwissHourlyView extends WatchUi.View {
    const INK = 0xF1F8FB;
    const MUTED = 0xA3BAC6;
    const QUIET = 0x7894A3;
    const ACCENT = 0x78D7EF;
    const RULE = 0x244558;
    const NAVY = 0x04131F;
    const SEA = 0x071D2D;
    const SEA_DEEP = 0x092538;
    const PAGE_SIZE = 6;
    const ROW_TOP = 158;
    const ROW_HEIGHT = 38;

    var service;
    var startDayIndex;
    var dayIndex;
    var icons;
    var page = 0;
    var titleFont;
    var labelFont;
    var valueFont;
    var smallFont;

    function initialize(weatherService, index, weatherIcons) {
        View.initialize();
        service = weatherService;
        startDayIndex = index;
        dayIndex = index;
        icons = weatherIcons;
        titleFont = Graphics.getVectorFont({:face => "RobotoCondensedBold", :size => 32});
        labelFont = Graphics.getVectorFont({:face => "RobotoRegular", :size => 18});
        valueFont = Graphics.getVectorFont({:face => "RobotoCondensedBold", :size => 27});
        smallFont = Graphics.getVectorFont({:face => "RobotoRegular", :size => 14});
    }

    function onShow() {
        service.ensureHourlyForDay(dayIndex);
    }

    function onHide() {
        // Also stop a pending GPS attempt if the app closes from this page.
        service.stop();
    }

    function nextPage() {
        advancePastEmptyDay();
        var rows = service.getHourlyForDay(dayIndex);
        var available = visibleHourCount(dayIndex);
        if (rows != null && available > 0 && page + 1 < pageCount(available)) {
            page += 1;
            WatchUi.requestUpdate();
            return;
        }
        var nextDay = nextDayWithHours(dayIndex);
        if (nextDay != null) {
            dayIndex = nextDay;
            page = 0;
            WatchUi.requestUpdate();
        }
    }

    function previousPage() {
        if (page > 0) {
            page -= 1;
            WatchUi.requestUpdate();
            return;
        }
        var previousDay = previousDayWithHours(dayIndex);
        if (previousDay != null) {
            dayIndex = previousDay;
            page = pageCount(visibleHourCount(dayIndex)) - 1;
            WatchUi.requestUpdate();
        }
    }

    function onUpdate(dc) {
        advancePastEmptyDay();
        var width = dc.getWidth();
        drawBackground(dc, width);
        var date = selectedDate();
        var rows = service.getHourlyForDay(dayIndex);
        var cadence = "HOURLY FORECAST";
        if (rows != null && rows.size() > 1 && rows[1][0] - rows[0][0] >= 3) {
            cadence = "3-HOUR FORECAST";
        }
        dc.setColor(ACCENT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(width / 2, 34, smallFont, cadence, Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(INK, Graphics.COLOR_TRANSPARENT);
        dc.drawText(width / 2, 56, titleFont, dateLabel(date), Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(QUIET, Graphics.COLOR_TRANSPARENT);
        dc.drawText(76, 71, smallFont, "BACK", Graphics.TEXT_JUSTIFY_LEFT);

        if (rows == null || rows.size() == 0) {
            drawEmpty(dc, width, service.isRefreshing() ?
                      service.getStatus() : "No hourly data yet",
                      "CHECK PHONE · RETRYING");
            return;
        }
        var first = firstVisibleIndex(rows, date);
        var available = rows.size() - first;
        if (available <= 0) {
            drawEmpty(dc, width, "No hours left today", "BACK TO 3-DAY VIEW");
            return;
        }
        var pages = pageCount(available);
        if (page >= pages) { page = pages - 1; }
        var begin = first + page * PAGE_SIZE;
        var end = begin + PAGE_SIZE;
        if (end > rows.size()) { end = rows.size(); }

        dc.setColor(QUIET, Graphics.COLOR_TRANSPARENT);
        dc.drawText(width / 2, 105, smallFont,
                    (page + 1).toString() + " / " + pages.toString(),
                    Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(69, 130, smallFont, "TIME", Graphics.TEXT_JUSTIFY_LEFT);
        dc.drawText(234, 130, smallFont, "TEMP", Graphics.TEXT_JUSTIFY_RIGHT);
        dc.drawText(314, 130, smallFont, "RAIN", Graphics.TEXT_JUSTIFY_RIGHT);
        dc.drawText(389, 130, smallFont, "km/h", Graphics.TEXT_JUSTIFY_RIGHT);
        dc.setColor(RULE, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(65, 151, 389, 151);

        for (var i = begin; i < end; i += 1) {
            drawHour(dc, rows[i], i - begin);
        }
        dc.setColor(QUIET, Graphics.COLOR_TRANSPARENT);
        var from = page * PAGE_SIZE + 1;
        var to = from + end - begin - 1;
        var footer = from.toString() + "-" + to.toString() + " / " +
                     available.toString();
        if (page + 1 < pages) {
            footer += "  ·  SWIPE FOR MORE";
        } else {
            var nextDay = nextDayWithHours(dayIndex);
            if (nextDay != null) {
                footer += "  ·  NEXT " + dateLabel(dateForDay(nextDay)).substring(0, 3);
            }
        }
        dc.drawText(width / 2, 405, smallFont, footer, Graphics.TEXT_JUSTIFY_CENTER);
    }

    function drawHour(dc, hour, row) {
        var y = ROW_TOP + row * ROW_HEIGHT;
        if (row % 2 == 0) {
            dc.setColor(SEA_DEEP, SEA_DEEP);
            dc.fillRectangle(62, y, 330, ROW_HEIGHT);
        }
        dc.setColor(MUTED, Graphics.COLOR_TRANSPARENT);
        dc.drawText(69, y + 7, labelFont,
                    hour[0].format("%02d") + ":00", Graphics.TEXT_JUSTIFY_LEFT);
        dc.drawBitmap(135, y + 1,
                      icons[MeteoSwissConditions.iconIndex(hour[4])]);
        dc.setColor(INK, Graphics.COLOR_TRANSPARENT);
        dc.drawText(234, y + 2, valueFont,
                    formatNumber(hour[1], "°"), Graphics.TEXT_JUSTIFY_RIGHT);
        dc.setColor(ACCENT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(314, y + 7, labelFont,
                    formatNumber(hour[2], "%"), Graphics.TEXT_JUSTIFY_RIGHT);
        dc.setColor(MUTED, Graphics.COLOR_TRANSPARENT);
        dc.drawText(389, y + 7, labelFont,
                    formatNumber(hour[3], ""), Graphics.TEXT_JUSTIFY_RIGHT);
        dc.setColor(RULE, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(65, y + ROW_HEIGHT - 1, 389, y + ROW_HEIGHT - 1);
    }

    function drawEmpty(dc, width, message, hint) {
        dc.setColor(MUTED, Graphics.COLOR_TRANSPARENT);
        dc.drawText(width / 2, 221, labelFont, message, Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(QUIET, Graphics.COLOR_TRANSPARENT);
        dc.drawText(width / 2, 405, smallFont, hint,
                    Graphics.TEXT_JUSTIFY_CENTER);
    }

    function drawBackground(dc, width) {
        dc.setColor(NAVY, NAVY);
        dc.clear();
        dc.setColor(SEA, SEA);
        dc.fillCircle(width / 2, 515, 350);
        dc.setColor(SEA_DEEP, SEA_DEEP);
        dc.fillCircle(width / 2, 540, 300);
    }

    function selectedDate() {
        return dateForDay(dayIndex);
    }

    function dateForDay(index) {
        var weather = service.getWeather();
        if (weather == null || weather["forecast"] == null ||
            index < 0 || index >= weather["forecast"].size()) { return null; }
        return weather["forecast"][index]["date"];
    }

    function forecastCount() {
        var weather = service.getWeather();
        if (weather == null || weather["forecast"] == null) { return 0; }
        return weather["forecast"].size();
    }

    function visibleHourCount(index) {
        var rows = service.getHourlyForDay(index);
        if (rows == null) { return 0; }
        return rows.size() - firstVisibleIndex(rows, dateForDay(index));
    }

    function nextDayWithHours(index) {
        for (var day = index + 1; day < forecastCount(); day += 1) {
            if (visibleHourCount(day) > 0) { return day; }
        }
        return null;
    }

    function previousDayWithHours(index) {
        for (var day = index - 1; day >= startDayIndex; day -= 1) {
            if (visibleHourCount(day) > 0) { return day; }
        }
        return null;
    }

    function advancePastEmptyDay() {
        if (visibleHourCount(dayIndex) > 0) { return; }
        var nextDay = nextDayWithHours(dayIndex);
        if (nextDay != null) {
            dayIndex = nextDay;
            page = 0;
        }
    }

    function dateLabel(date) {
        if (date == null || date.length() < 10) { return "FORECAST"; }
        var moment = Gregorian.moment({
            :year => date.substring(0, 4).toNumber(),
            :month => date.substring(5, 7).toNumber(),
            :day => date.substring(8, 10).toNumber(),
            :hour => 12
        });
        var weekdays = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"];
        var months = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN",
                      "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"];
        var day = Gregorian.info(moment, Time.FORMAT_SHORT);
        return weekdays[day.day_of_week - 1] + " " +
               date.substring(8, 10) + " " + months[date.substring(5, 7).toNumber() - 1];
    }

    function firstVisibleIndex(rows, date) {
        if (date == null || !date.equals(todayKey())) { return 0; }
        var hour = System.getClockTime().hour;
        for (var i = 0; i < rows.size(); i += 1) {
            if (rows[i][0] >= hour) { return i; }
        }
        return rows.size();
    }

    function todayKey() {
        var current = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
        return current.year.format("%04d") + "-" +
               current.month.format("%02d") + "-" + current.day.format("%02d");
    }

    function pageCount(count) {
        return ((count + PAGE_SIZE - 1) / PAGE_SIZE).toNumber();
    }

    function formatNumber(value, suffix) {
        if (value == null) { return "--"; }
        return value.format("%.0f") + suffix;
    }
}

class MeteoSwissHourlyInputDelegate extends WatchUi.BehaviorDelegate {
    var view;

    function initialize(hourlyView) {
        BehaviorDelegate.initialize();
        view = hourlyView;
    }

    function onNextPage() as Lang.Boolean {
        view.nextPage();
        return true;
    }

    function onPreviousPage() as Lang.Boolean {
        view.previousPage();
        return true;
    }

    function onBack() as Lang.Boolean {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        return true;
    }

    function onTap(clickEvent as WatchUi.ClickEvent) as Lang.Boolean {
        var point = clickEvent.getCoordinates();
        if (point[0] < 140 && point[1] < 110) {
            WatchUi.popView(WatchUi.SLIDE_RIGHT);
        }
        return true;
    }
}
