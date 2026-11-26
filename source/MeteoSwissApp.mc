using Toybox.Application;
using Toybox.Lang;
using Toybox.WatchUi;

(:glance)
class MeteoSwissApp extends Application.AppBase {
    function initialize() {
        AppBase.initialize();
    }

    function getInitialView() {
        var view = new MeteoSwissView();
        return [view, new MeteoSwissInputDelegate(view)];
    }

    function getGlanceView() {
        return [new MeteoSwissGlanceView()];
    }

    function getGlanceTheme() {
        return AppBase.GLANCE_THEME_BLUE;
    }
}

class MeteoSwissInputDelegate extends WatchUi.BehaviorDelegate {
    var view;

    function initialize(weatherView) {
        BehaviorDelegate.initialize();
        view = weatherView;
    }

    function onSelect() as Lang.Boolean {
        // A touch tap also maps to Select. Let it reach onTap(), which has the
        // row coordinates needed to open the day the user actually touched.
        return false;
    }

    function onKey(keyEvent as WatchUi.KeyEvent) as Lang.Boolean {
        var key = keyEvent.getKey();
        if (key == WatchUi.KEY_ENTER || key == WatchUi.KEY_START) {
            view.selectOrRefresh();
            return true;
        }
        return false;
    }

    function onTap(clickEvent as WatchUi.ClickEvent) as Lang.Boolean {
        var point = clickEvent.getCoordinates();
        view.tapAt(point[0], point[1]);
        return true;
    }

    function onNextPage() as Lang.Boolean {
        view.selectNextDay();
        return true;
    }

    function onPreviousPage() as Lang.Boolean {
        view.selectPreviousDay();
        return true;
    }

    function onMenu() as Lang.Boolean {
        view.refresh();
        return true;
    }
}
