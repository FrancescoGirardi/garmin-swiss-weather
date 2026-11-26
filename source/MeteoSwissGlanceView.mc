using Toybox.Graphics;
using Toybox.Lang;
using Toybox.Time;
using Toybox.Time.Gregorian;
using Toybox.WatchUi;

// A cached summary in Garmin's glance list. Opening it runs the full app,
// which owns GPS and network refreshes. No radio work happens here.
(:glance)
class MeteoSwissGlanceView extends WatchUi.GlanceView {
    const INK = 0xF1F8FB;
    const MUTED = 0xA3BAC6;
    const ACCENT = 0x78D7EF;
    const BACKGROUND = 0x16243E;

    var titleFont;
    var valueFont;
    var detailFont;
    var today;
    var currentTemp;
    var icon;
    var lastFetch;

    function initialize() {
        GlanceView.initialize();
        titleFont = Graphics.getVectorFont({:face => "RobotoRegular", :size => 17});
        valueFont = Graphics.getVectorFont({:face => "RobotoCondensedBold", :size => 30});
        detailFont = Graphics.getVectorFont({:face => "RobotoRegular", :size => 14});
    }

    function onShow() {
        today = null;
        currentTemp = null;
        icon = null;
        lastFetch = null;
        var cache = new MeteoSwissCache().read();
        if (cache == null) { return; }
        lastFetch = cache["lastFetch"];
        var weather = cache["weather"] as Lang.Dictionary;
        var item = weather["forecast"][0] as Lang.Dictionary;
        if (item == null || !item["date"].equals(dateKey())) { return; }
        today = item;
        if (weather.hasKey("currentTemp")) {
            currentTemp = weather["currentTemp"];
        }
        var code = item.hasKey("weatherCode") ? item["weatherCode"] : null;
        var iconIds = [
            Rez.Drawables.WeatherSun, Rez.Drawables.WeatherPartCloud,
            Rez.Drawables.WeatherCloud, Rez.Drawables.WeatherRain,
            Rez.Drawables.WeatherSnow, Rez.Drawables.WeatherStorm,
            Rez.Drawables.WeatherFog, Rez.Drawables.WeatherUnknown
        ];
        icon = WatchUi.loadResource(iconIds[MeteoSwissConditions.iconIndex(code)]);
    }

    function onUpdate(dc) {
        var width = dc.getWidth();
        dc.setColor(BACKGROUND, BACKGROUND);
        dc.clear();
        dc.setColor(MUTED, Graphics.COLOR_TRANSPARENT);
        dc.drawText(10, 12, titleFont, "TODAY", Graphics.TEXT_JUSTIFY_LEFT);
        if (lastFetch != null) {
            dc.drawText(width - 12, 15, detailFont, ageLabel(), Graphics.TEXT_JUSTIFY_RIGHT);
        }

        if (today == null) {
            dc.setColor(INK, Graphics.COLOR_TRANSPARENT);
            dc.drawText(10, 57, titleFont, "Open to refresh", Graphics.TEXT_JUSTIFY_LEFT);
            return;
        }

        if (icon != null) { dc.drawBitmap(9, 55, icon); }
        dc.setColor(INK, Graphics.COLOR_TRANSPARENT);
        if (currentTemp != null) {
            dc.drawText(53, 47, valueFont,
                        formatNumber(currentTemp) + "°", Graphics.TEXT_JUSTIFY_LEFT);
        } else {
            dc.drawText(53, 47, valueFont,
                        formatNumber(today["highTemp"]) + "° / " +
                        formatNumber(today["lowTemp"]) + "°", Graphics.TEXT_JUSTIFY_LEFT);
        }
        dc.setColor(ACCENT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(width - 12, 47, valueFont,
                    formatNumber(today["precipProbability"]) + "%", Graphics.TEXT_JUSTIFY_RIGHT);
        dc.setColor(MUTED, Graphics.COLOR_TRANSPARENT);
        var range = "HIGH " + formatNumber(today["highTemp"]) + "°  LOW " +
                    formatNumber(today["lowTemp"]) + "°";
        dc.drawText(53, 91, detailFont, range, Graphics.TEXT_JUSTIFY_LEFT);
        dc.drawText(width - 12, 91, detailFont, "RAIN", Graphics.TEXT_JUSTIFY_RIGHT);
    }

    function dateKey() {
        var current = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
        return current.year.format("%04d") + "-" +
               current.month.format("%02d") + "-" + current.day.format("%02d");
    }

    function ageLabel() {
        var age = Time.now().value() - lastFetch;
        if (age < 0) { age = 0; }
        if (age < 60) { return "Just updated"; }
        if (age < 3600) { return (age / 60).format("%.0f") + "m old"; }
        if (age < 86400) { return (age / 3600).format("%.0f") + "h old"; }
        return (age / 86400).format("%.0f") + "d old";
    }

    function formatNumber(value) {
        if (value == null) { return "--"; }
        return value.format("%.0f");
    }
}
