import QtQuick 2.12
import QtQuick.Layouts 1.12

// A row of a settings page: a label, a list and what follows it (OK). In place of a RowLayout:
// with everything in one row it lays out as one (one column per shown item, columnSpacing =
// spacing). Modern look (T-593, decision 18.11): the list keeps the width of its text, at most
// half the window (UiComboBox Layout.minimumWidth), and when the label then has less room than
// its longest word, or the value of the list is wider than half the window, the row is stacked -
// the label across the row, the list and the rest one line lower, the list across the free width
// (UiComboBox Layout.fillWidth). The label spans
// the row with "Layout.columnSpan: parent.stackedRow ? parent.columns : 1".
// Items with visible: false take no cell (Qt 5.15.0 QQuickLayout::shouldIgnoreItem,
// qquicklayout.cpp:771-793; QQuickGridLayout::insertLayoutItems, qquicklinearlayout.cpp:675).
GridLayout {
    id: row

    // As the "spacing" of a RowLayout. Not set - the one of the style, as a RowLayout: both take
    // QGridLayoutEngine::spacing with the style info (8 x DPI/96 on Android and iOS, 5 elsewhere;
    // Qt 5.15.0 qquicklinearlayout.cpp:529 and 838, qquicklayoutstyleinfo.cpp:51-66), and the setter
    // skips NaN (qquicklinearlayout.cpp:535)
    property real spacing: NaN
    columnSpacing: spacing
    // Stacked: the items right under the label, ~6 dp from its glyphs (~3.5 dp of the line under them) to
    // what is drawn (T-593, mockup notes/mockups/t593-field-gap-2026-11-19, decision 19.11 - variant 3). A
    // field, a list and OK keep a top inset over their background (6 dp: UiTextField.modernInset,
    // UiComboBox, UiButton) - -4 with them; the accent swatches have none - 2. A user row spacing is
    // taken as it is, a negative one too: Qt 5.15.0 qgridlayoutengine.cpp:1349-1351 (no clamp), :94-100
    // (the total height), :466-477 (the position of the next row); the same in 6.8 (:1348-1349, :62-68, :446)
    readonly property real stackInset: {
        var m = -1
        for (var i = 0; i < others.length; i++) {
            var t = others[i].topInset !== undefined ? others[i].topInset : 0
            m = m < 0 ? t : Math.min(m, t)
        }
        return Math.max(0, m)
    }
    rowSpacing: stackedRow ? 2 - stackInset : 4

    // the first shown label (a text that wraps) and the other shown items of the row
    readonly property Item label: {
        for (var i = 0; i < children.length; i++) {
            var c = children[i]
            if (c.visible && c.wrapMode !== undefined && c.text !== undefined)
                return c
        }
        return null
    }
    readonly property var others: {
        var list = []
        for (var i = 0; i < children.length; i++)
            if (children[i].visible && children[i] !== label)
                list.push(children[i])
        return list
    }

    FontMetrics {
        id: metrics
        font: row.label ? row.label.font : Qt.application.font
    }

    // the width of the longest word of the label: less room than that cuts the word
    readonly property real wordWidth: {
        if (!label)
            return 0
        var words = String(label.text).split(" ")
        var w = 0
        for (var i = 0; i < words.length; i++)
            w = Math.max(w, metrics.advanceWidth(words[i]))
        return Math.ceil(w) + (label.leftPadding || 0) + (label.rightPadding || 0)
    }
    // a list of the modern look on a settings page (UiComboBox): in a row it takes at most half the
    // window (its Layout.minimumWidth); the other items (OK, the swatches of the accent colour) keep
    // their own width - capped, the seven swatches at 130 % passed for narrower than they are and
    // the label ran under them (T-593, phone 19.11). UiButton has inTypeScalePage too: an OK is
    // narrow, and a button wider than half the window is better a line lower as well
    function isList(item) {
        return item.inTypeScalePage !== undefined
    }
    // what the other items take in one row
    readonly property real othersWidth: {
        var w = 0
        for (var i = 0; i < others.length; i++)
            w += (isList(others[i]) ? Math.min(others[i].implicitWidth, window.width / 2)
                                    : others[i].implicitWidth) + columnSpacing
        return w
    }
    // a list whose value is wider than half the window: in a row it was cut ("Глобальний
    // (garmin." of Garmin Server, a short label - T-593, phone 19.11); stacked it gets the row
    readonly property bool listCut: {
        for (var i = 0; i < others.length; i++)
            if (isList(others[i]) && others[i].implicitWidth > window.width / 2)
                return true
        return false
    }
    // a field for a long text (UiTextField.wideText: an e-mail, a login, an address) - always under
    // the label, across the row (T-593, decision 19.11)
    readonly property bool wideField: {
        for (var i = 0; i < others.length; i++)
            if (others[i].wideText === true)
                return true
        return false
    }
    // the width the row gets: the one of its column (its own follows the stacking) less its side margins -
    // in the modern look the frames give the row the padding of its card as Layout.left/rightMargin
    // (UiSettingFrames.setMargin): without them the accent swatches at 130 % passed by ~13 dp and ran over
    // a wrapped "Акцентний колір" (T-593, phone 19.11, beta-3028)
    readonly property real roomWidth: (parent ? parent.width : width) - Layout.leftMargin - Layout.rightMargin

    readonly property bool stackedRow: window.ui.modern && label !== null && others.length > 0
                                       && (wordWidth + othersWidth > roomWidth || listCut || wideField)
    columns: Math.max(1, stackedRow ? others.length : others.length + (label ? 1 : 0))
}
