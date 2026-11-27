// Live weather on Plasma: caelestia's GenesiWeatherFx over the wallpaper and
// under every window. The window takes no input at all (PluginWindow's
// passthrough), so the desktop under it still gets every click. The sky comes
// from Open-Meteo through the host, refreshed every half hour.
import QtQuick

GenesiWeatherFx {
    code: host.weather.code ?? 0
    wind: host.weather.wind ?? 0.25
    running: true
}
