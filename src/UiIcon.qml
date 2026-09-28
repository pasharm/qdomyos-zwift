import QtQuick 2.12
import QtQuick.Shapes 1.12
import QtQuick.Window 2.12
import "UiIcons.js" as UiIcons

// Monochrome Material Symbols icon drawn from its SVG path, so it takes any colour
// and needs no QtSvg module. Name is a key of UiIcons.paths.
Item {
    id: icon
    property string name: ""
    property color color: "white"

    implicitWidth: 24
    implicitHeight: 24

    // Shape has no antialiasing of its own: render it into a multisampled layer
    layer.enabled: visible
    layer.samples: 4
    layer.smooth: true
    layer.textureSize: Qt.size(width * Screen.devicePixelRatio, height * Screen.devicePixelRatio)

    Shape {
        // The symbols use viewBox 0 -960 960 960: y runs from -960 to 0, so the
        // origin sits on the bottom edge
        y: icon.height
        width: 960
        height: 960
        scale: icon.width / 960
        transformOrigin: Item.TopLeft

        ShapePath {
            fillColor: icon.color
            strokeColor: "transparent"
            strokeWidth: 0
            PathSvg { path: UiIcons.paths[icon.name] || "" }
        }
    }
}
