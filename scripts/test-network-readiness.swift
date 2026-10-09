import Foundation

@main
enum TestNetworkReadiness {
    static func main() {
        expect(
            NetworkReadiness.from(snapshot(wifiOn: true, associated: true, ssid: "Lars iPhone", route: true))
                == .ready(networkName: "Lars iPhone"),
            "hotspot with SSID"
        )
        expect(
            NetworkReadiness.from(snapshot(wifiOn: true, associated: true, ssid: nil, route: true))
                == .ready(networkName: nil),
            "associated without Location SSID"
        )
        expect(
            NetworkReadiness.from(snapshot(wifiOn: true, associated: true, ssid: "  ", route: false))
                == .ready(networkName: nil),
            "associated, DHCP still settling"
        )
        expect(
            NetworkReadiness.from(snapshot(wifiOn: false, associated: false, ssid: nil, route: true))
                == .ready(networkName: nil),
            "ethernet/other default route"
        )
        expect(
            NetworkReadiness.from(snapshot(wifiOn: false, associated: false, ssid: nil, route: false))
                == .wifiOff,
            "wifi off and offline"
        )
        expect(
            NetworkReadiness.from(snapshot(wifiOn: true, associated: false, ssid: nil, route: false))
                == .notJoined,
            "wifi on but not joined"
        )

        let off = NetworkReadiness.from(snapshot(wifiOn: false, associated: false, ssid: nil, route: false))
        expect(off.shouldWarnBeforeVibe, "wifi off warns")
        expect(off.menuLabel == "Wi-Fi off", "wifi off label")
        expect(!off.alertBody.isEmpty, "wifi off body")

        let isolated = NetworkReadiness.from(snapshot(wifiOn: true, associated: false, ssid: nil, route: false))
        expect(isolated.shouldWarnBeforeVibe, "not joined warns")
        expect(isolated.menuLabel == "no hotspot", "not joined label")

        let ready = NetworkReadiness.from(snapshot(wifiOn: true, associated: true, ssid: "Cafe", route: true))
        expect(!ready.shouldWarnBeforeVibe, "ready does not warn")
        expect(ready.menuLabel == "Cafe", "ready label uses SSID")

        print("OK")
    }

    static func expect(_ cond: Bool, _ msg: String) {
        if !cond {
            fputs("FAIL \(msg)\n", stderr)
            exit(1)
        }
    }

    static func snapshot(
        wifiOn: Bool,
        associated: Bool,
        ssid: String?,
        route: Bool
    ) -> NetworkSnapshot {
        NetworkSnapshot(
            wifiHardwareOn: wifiOn,
            wifiAssociated: associated,
            ssid: ssid,
            hasDefaultRoute: route
        )
    }
}
