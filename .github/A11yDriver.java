// Test only (T-222): send the app the accessibility actions TalkBack sends, without TalkBack
// (the emulator image has none). Runs through app_process as the shell, with the UiAutomation
// connection uiautomator uses, so only one may run at a time and no dump meanwhile.
//
//   CLASSPATH=/data/local/tmp/a11y.jar app_process / A11yDriver step [step ...]
//   step: list | sleep:<ms> | find:<desc> | focus:<desc> | click:<desc> | fwd:<desc> | back:<desc>
// <desc> is the start of a content description; the first node in tree order that matches is used.
import android.os.HandlerThread;
import android.os.Looper;
import android.app.UiAutomation;
import android.graphics.Rect;
import android.view.accessibility.AccessibilityNodeInfo;
import java.lang.reflect.Constructor;

public class A11yDriver {
    private static UiAutomation automation;

    public static void main(String[] args) throws Exception {
        // AccessibilityInteractionClient makes a Handler on the main looper, which app_process lacks
        Looper.prepareMainLooper();
        HandlerThread thread = new HandlerThread("A11yDriver");
        thread.start();
        Class<?> connectionInterface = Class.forName("android.app.IUiAutomationConnection");
        Object connection = Class.forName("android.app.UiAutomationConnection").getConstructor().newInstance();
        Constructor<UiAutomation> constructor =
                UiAutomation.class.getConstructor(Looper.class, connectionInterface);
        automation = constructor.newInstance(thread.getLooper(), connection);
        UiAutomation.class.getMethod("connect").invoke(automation);
        Thread.sleep(1500);
        try {
            for (String step : args) {
                run(step);
            }
        } finally {
            UiAutomation.class.getMethod("disconnect").invoke(automation);
            thread.quitSafely();
        }
    }

    private static void run(String step) throws Exception {
        int colon = step.indexOf(':');
        String verb = colon < 0 ? step : step.substring(0, colon);
        String arg = colon < 0 ? "" : step.substring(colon + 1);
        if (verb.equals("sleep")) {
            Thread.sleep(Long.parseLong(arg));
            return;
        }
        AccessibilityNodeInfo root = automation.getRootInActiveWindow();
        if (root == null) {
            System.out.println(step + ": NO ROOT");
            return;
        }
        if (verb.equals("list")) {
            list(root, 0);
            return;
        }
        AccessibilityNodeInfo node = find(root, arg);
        if (node == null) {
            System.out.println(step + ": NOT FOUND");
            return;
        }
        if (verb.equals("find")) {
            System.out.println(step + ": " + describe(node));
            return;
        }
        int action;
        if (verb.equals("focus")) {
            action = AccessibilityNodeInfo.ACTION_ACCESSIBILITY_FOCUS;
        } else if (verb.equals("click")) {
            action = AccessibilityNodeInfo.ACTION_CLICK;
        } else if (verb.equals("fwd")) {
            action = AccessibilityNodeInfo.ACTION_SCROLL_FORWARD;
        } else if (verb.equals("back")) {
            action = AccessibilityNodeInfo.ACTION_SCROLL_BACKWARD;
        } else {
            System.out.println(step + ": UNKNOWN STEP");
            return;
        }
        System.out.println(step + ": before " + describe(node));
        boolean result = node.performAction(action);
        Thread.sleep(1000);
        AccessibilityNodeInfo after = find(automation.getRootInActiveWindow(), arg);
        System.out.println(step + ": returned " + result + ", after "
                + (after == null ? "NOT FOUND by the same start" : describe(after)));
    }

    private static AccessibilityNodeInfo find(AccessibilityNodeInfo node, String start) {
        if (node == null) {
            return null;
        }
        CharSequence desc = node.getContentDescription();
        if (desc != null && desc.toString().startsWith(start)) {
            return node;
        }
        for (int i = 0; i < node.getChildCount(); i++) {
            AccessibilityNodeInfo found = find(node.getChild(i), start);
            if (found != null) {
                return found;
            }
        }
        return null;
    }

    private static void list(AccessibilityNodeInfo node, int depth) {
        if (node == null) {
            return;
        }
        StringBuilder indent = new StringBuilder();
        for (int i = 0; i < depth; i++) {
            indent.append("  ");
        }
        System.out.println(indent + describe(node));
        for (int i = 0; i < node.getChildCount(); i++) {
            list(node.getChild(i), depth + 1);
        }
    }

    private static String describe(AccessibilityNodeInfo node) {
        Rect bounds = new Rect();
        node.getBoundsInScreen(bounds);
        StringBuilder actions = new StringBuilder();
        for (AccessibilityNodeInfo.AccessibilityAction a : node.getActionList()) {
            actions.append(a.getId()).append(' ');
        }
        return "'" + node.getContentDescription() + "' class=" + node.getClassName()
                + " bounds=" + bounds.toShortString()
                + " visible=" + node.isVisibleToUser()
                + " clickable=" + node.isClickable()
                + " focusable=" + node.isFocusable()
                + " checkable=" + node.isCheckable() + " checked=" + node.isChecked()
                + " a11yFocused=" + node.isAccessibilityFocused()
                + " actions=[" + actions.toString().trim() + "]";
    }
}
