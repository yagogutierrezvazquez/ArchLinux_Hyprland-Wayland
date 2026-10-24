pragma Singleton

// Session-wide state shared between Quickshell pieces (resets on login).
import Quickshell

Singleton {
    // "Stay awake" toggle: the dock holds the idle inhibitor (it needs an
    // always-mapped window; the dashboard is hidden most of the time).
    property bool stayAwake: false
}
