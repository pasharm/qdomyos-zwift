import QtQuick 2.12
import QtQuick.Controls 2.12
import QtQuick.Controls.Material 2.12

// ComboBox of the settings pages and the wizard. The Material style paints the box and its
// list with dialogColor, which follows Material.background: the modern look sets that to the
// page colour, so the box vanished into the page. Here it is one step lighter than the page.
// Classic look: the stock binding (transparent only for a flat box).
ComboBox {
    Material.background: window.ui.modern ? window.ui.surfaceHighest : (flat ? "transparent" : undefined)
}
