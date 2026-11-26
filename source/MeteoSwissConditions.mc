using Toybox.Lang;

// Daily WMO weather codes are shared by the full view and the glance.
(:glance)
class MeteoSwissConditions {
    static function iconIndex(code) {
        if (!(code instanceof Lang.Number)) { return 7; }
        var number = code as Lang.Number;
        if (number == 0 || number == 1) { return 0; }
        if (number == 2) { return 1; }
        if (number == 3) { return 2; }
        if (number == 45 || number == 48) { return 6; }
        if (number >= 51 && number <= 67) { return 3; }
        if (number >= 71 && number <= 77) { return 4; }
        if (number >= 80 && number <= 82) { return 3; }
        if (number == 85 || number == 86) { return 4; }
        if (number >= 95 && number <= 99) { return 5; }
        return 7;
    }
}
