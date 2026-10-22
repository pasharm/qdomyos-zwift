// Accessibility test for the android-emulator-test job: sends QZ the actions a screen reader such
// as TalkBack sends, without TalkBack, so it runs on every emulator image. It connects as the
// shell's UiAutomation, as uiautomator does, which turns accessibility on in the app, then:
// - moves the accessibility focus over the app's nodes (QZ scrolls the focused item into view,
//   CustomQtActivity -> nativeScrollToAccessibleObject),
// - scrolls a scrollable node forward and back (a spin box or a list),
// - presses a button whose description starts with the given text (QZ presses a Qt button itself,
//   nativeAccessibleClick, and answers true; Qt 5.15 alone answers false for a button).
// Every line it prints starts with OK, FAIL, SKIP or INFO; the last one is DONE.
//
//   CLASSPATH=/data/local/tmp/a11y-test.jar app_process / AccessibilityTest [button]
import android.app.UiAutomation;
import android.os.HandlerThread;
import android.os.Looper;
import android.view.accessibility.AccessibilityNodeInfo;
import java.lang.reflect.Constructor;
import java.util.ArrayList;
import java.util.List;

public class AccessibilityTest {
    private static final String PACKAGE = "org.cagnulen.qdomyoszwift";
    private static UiAutomation automation;

    public static void main(String[] args) throws Exception {
        // AccessibilityInteractionClient makes a Handler on the main looper, which app_process lacks
        Looper.prepareMainLooper();
        HandlerThread thread = new HandlerThread("AccessibilityTest");
        thread.start();
        Class<?> connectionInterface = Class.forName("android.app.IUiAutomationConnection");
        Object connection = Class.forName("android.app.UiAutomationConnection").getConstructor().newInstance();
        Constructor<UiAutomation> constructor = UiAutomation.class.getConstructor(Looper.class, connectionInterface);
        automation = constructor.newInstance(thread.getLooper(), connection);
        UiAutomation.class.getMethod("connect").invoke(automation);
        try {
            run(args);
        } finally {
            UiAutomation.class.getMethod("disconnect").invoke(automation);
            thread.quitSafely();
        }
        System.out.println("DONE");
    }

    private static void run(String[] buttons) throws Exception {
        List<AccessibilityNodeInfo> nodes = waitForAppNodes();
        if (nodes.isEmpty()) {
            AccessibilityNodeInfo root = automation.getRootInActiveWindow();
            CharSequence active = root == null ? null : root.getPackageName();
            String nativeText = firstText(root);
            if (active == null || !active.toString().equals(PACKAGE)) {
                // e.g. an "isn't responding" dialog of the system over QZ on a slow emulator
                System.out.println("SKIP the active window is " + active + ", not QZ");
            } else if (nativeText != null) {
                // QZ's own Android dialog, not the Qt view: e.g. "Permissions Required" on the
                // emulator images without Bluetooth (the back button test skips them for it too)
                System.out.println("SKIP a native window of QZ is in front: '" + nativeText + "'");
            } else {
                System.out.println("FAIL no accessibility node of QZ with a description: Qt accessibility is off");
            }
            return;
        }
        System.out.println("OK " + nodes.size() + " nodes of QZ with a description");
        for (AccessibilityNodeInfo node : nodes) {
            System.out.println("INFO node " + describe(node));
        }

        int focused = 0;
        for (AccessibilityNodeInfo node : nodes) {
            if (focused == 10) {
                break;
            }
            if (node.isFocusable()) {
                if (!node.performAction(AccessibilityNodeInfo.ACTION_ACCESSIBILITY_FOCUS)) {
                    System.out.println("FAIL focus not taken by " + describe(node));
                    return;
                }
                focused++;
                Thread.sleep(300);
            }
        }
        if (focused == 0) {
            System.out.println("FAIL no focusable node of QZ");
            return;
        }
        System.out.println("OK focus moved over " + focused + " nodes");

        if (buttons.length == 0) {
            System.out.println("FAIL no button to press given");
            return;
        }
        for (String button : buttons) {
            if (!press(button)) {
                return;
            }
        }
    }

    // Presses the first clickable node whose description starts with the button's text ("U+25C4"
    // stands for that character, as adb shell arguments are not safe outside ASCII)
    private static boolean press(String button) throws Exception {
        if (button.startsWith("U+")) {
            button = new String(Character.toChars(Integer.parseInt(button.substring(2), 16)));
        }
        AccessibilityNodeInfo target = null;
        for (AccessibilityNodeInfo node : appNodes()) {
            CharSequence description = node.getContentDescription();
            if (node.isClickable() && description != null && description.toString().startsWith(button)) {
                target = node;
                break;
            }
        }
        if (target == null) {
            System.out.println("FAIL no button '" + button + "' on screen");
            return false;
        }
        String before = snapshot(appNodes());
        if (!target.performAction(AccessibilityNodeInfo.ACTION_CLICK)) {
            System.out.println("FAIL press not handled by QZ: " + describe(target));
            return false;
        }
        Thread.sleep(2000);
        List<AccessibilityNodeInfo> after = appNodes();
        System.out.println("INFO screen " + (snapshot(after).equals(before) ? "unchanged" : "changed") + " after the press");
        for (AccessibilityNodeInfo node : after) {
            System.out.println("INFO node " + describe(node));
        }
        System.out.println("OK pressed " + describe(target));

        // TODO-EXPLORE: what is scrollable after the press, to choose the strict checks
        for (AccessibilityNodeInfo node : after) {
            if (node.isScrollable()) {
                boolean forward = node.performAction(AccessibilityNodeInfo.ACTION_SCROLL_FORWARD);
                Thread.sleep(500);
                boolean backward = node.performAction(AccessibilityNodeInfo.ACTION_SCROLL_BACKWARD);
                Thread.sleep(500);
                System.out.println("INFO scrolled " + describe(node) + ": forward " + forward + ", backward " + backward);
            }
        }
        return true;
    }

    // What a screen reader can tell apart: names, states and places of the nodes
    private static String snapshot(List<AccessibilityNodeInfo> nodes) {
        StringBuilder out = new StringBuilder();
        android.graphics.Rect bounds = new android.graphics.Rect();
        for (AccessibilityNodeInfo node : nodes) {
            node.getBoundsInScreen(bounds);
            out.append(node.getContentDescription()).append(' ').append(node.isChecked()).append(' ')
                    .append(node.isEnabled()).append(' ').append(bounds.toShortString()).append('\n');
        }
        return out.toString();
    }

    // Qt adds its accessibility nodes once accessibility is on: wait for them up to 20 s
    private static List<AccessibilityNodeInfo> waitForAppNodes() throws Exception {
        for (int i = 0; i < 40; i++) {
            List<AccessibilityNodeInfo> nodes = appNodes();
            if (!nodes.isEmpty()) {
                return nodes;
            }
            Thread.sleep(500);
        }
        return new ArrayList<>();
    }

    private static List<AccessibilityNodeInfo> appNodes() {
        List<AccessibilityNodeInfo> out = new ArrayList<>();
        AccessibilityNodeInfo root = automation.getRootInActiveWindow();
        if (root != null && root.getPackageName() != null && root.getPackageName().toString().equals(PACKAGE)) {
            collect(root, out);
        }
        return out;
    }

    private static void collect(AccessibilityNodeInfo node, List<AccessibilityNodeInfo> out) {
        if (node == null) {
            return;
        }
        CharSequence description = node.getContentDescription();
        if (description != null && description.length() > 0) {
            out.add(node);
        }
        for (int i = 0; i < node.getChildCount(); i++) {
            collect(node.getChild(i), out);
        }
    }

    // The first text of a native Android view in the tree; Qt sets descriptions, not texts
    private static String firstText(AccessibilityNodeInfo node) {
        if (node == null) {
            return null;
        }
        CharSequence text = node.getText();
        if (text != null && text.length() > 0) {
            return text.toString();
        }
        for (int i = 0; i < node.getChildCount(); i++) {
            String found = firstText(node.getChild(i));
            if (found != null) {
                return found;
            }
        }
        return null;
    }

    private static String describe(AccessibilityNodeInfo node) {
        return "'" + node.getContentDescription() + "' class=" + node.getClassName()
                + " clickable=" + node.isClickable() + " focusable=" + node.isFocusable()
                + " scrollable=" + node.isScrollable();
    }
}
