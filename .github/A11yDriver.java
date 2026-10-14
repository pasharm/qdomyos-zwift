// Test only (T-222): send the app the accessibility actions TalkBack sends, without TalkBack
// (the emulator image has none). Runs through app_process as the shell, with the UiAutomation
// connection uiautomator uses, so only one may run at a time and no dump meanwhile.
//
//   CLASSPATH=/data/local/tmp/a11y.jar app_process / A11yDriver [--keep] step [step ...]
//   step: list | sleep:<ms> | find:<desc> | focus:<desc> | click:<desc> | fwd:<desc> | back:<desc>
//         | swipe:right|left|up|down | dtap | touch:<desc> | focused | mark:<text>
// <desc> is the start of a content description; the first node in tree order that matches is used.
// --keep: connect without switching the other accessibility services off, for a run with the
// real TalkBack; then the gesture steps go to its touch explorer, as a finger would.
import android.os.HandlerThread;
import android.os.Looper;
import android.os.SystemClock;
import android.util.Log;
import android.view.InputDevice;
import android.view.InputEvent;
import android.view.MotionEvent;
import android.app.UiAutomation;
import android.graphics.Rect;
import android.view.accessibility.AccessibilityNodeInfo;
import java.lang.reflect.Constructor;
import java.lang.reflect.Method;

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
        int first = 0;
        if (args.length > 0 && args[0].equals("--keep")) {
            // UiAutomation.FLAG_DONT_SUPPRESS_ACCESSIBILITY_SERVICES
            UiAutomation.class.getMethod("connect", int.class).invoke(automation, 1);
            first = 1;
        } else {
            UiAutomation.class.getMethod("connect").invoke(automation);
        }
        Thread.sleep(1500);
        try {
            for (int i = first; i < args.length; i++) {
                run(args[i]);
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
        if (verb.equals("mark")) {
            Log.i("A11yDriver", "mark " + arg);
            System.out.println("mark " + arg);
            return;
        }
        if (verb.equals("swipe")) {
            Log.i("A11yDriver", step);
            int dx = arg.equals("right") ? 1 : arg.equals("left") ? -1 : 0;
            int dy = arg.equals("down") ? 1 : arg.equals("up") ? -1 : 0;
            stroke(720 - dx * 350, 1300 - dy * 350, 720 + dx * 350, 1300 + dy * 350, 200);
            Thread.sleep(2500);
            printFocused(step);
            return;
        }
        if (verb.equals("dtap")) {
            Log.i("A11yDriver", step);
            stroke(720, 1300, 720, 1300, 50);
            Thread.sleep(80);
            stroke(720, 1300, 720, 1300, 50);
            Thread.sleep(2500);
            printFocused(step);
            return;
        }
        if (verb.equals("focused")) {
            printFocused(step);
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
        if (verb.equals("touch")) {
            Rect bounds = new Rect();
            node.getBoundsInScreen(bounds);
            Log.i("A11yDriver", step + " at " + bounds.centerX() + "," + bounds.centerY());
            System.out.println(step + ": at " + bounds.centerX() + "," + bounds.centerY() + " " + describe(node));
            // a finger that rests: touch exploration, not a tap
            stroke(bounds.centerX(), bounds.centerY(), bounds.centerX() + 4, bounds.centerY() + 4, 600);
            Thread.sleep(2500);
            printFocused(step);
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

    private static void printFocused(String step) {
        AccessibilityNodeInfo root = automation.getRootInActiveWindow();
        AccessibilityNodeInfo focused = root == null ? null : root.findFocus(AccessibilityNodeInfo.FOCUS_ACCESSIBILITY);
        System.out.println(step + ": focused " + (focused == null ? "NONE" : describe(focused)));
    }

    // One finger from (x1, y1) to (x2, y2) in ms, as the touch screen reports it
    private static void stroke(int x1, int y1, int x2, int y2, long ms) throws Exception {
        int moves = 10;
        long down = SystemClock.uptimeMillis();
        inject(MotionEvent.obtain(down, down, MotionEvent.ACTION_DOWN, x1, y1, 0));
        for (int i = 1; i <= moves; i++) {
            Thread.sleep(ms / moves);
            float x = x1 + (x2 - x1) * i / (float) moves;
            float y = y1 + (y2 - y1) * i / (float) moves;
            inject(MotionEvent.obtain(down, SystemClock.uptimeMillis(), MotionEvent.ACTION_MOVE, x, y, 0));
        }
        inject(MotionEvent.obtain(down, SystemClock.uptimeMillis(), MotionEvent.ACTION_UP, x2, y2, 0));
    }

    private static Method toFilter;
    private static boolean toFilterLooked;

    // Through the accessibility input filter (TalkBack's touch explorer), API 34+ test hook
    private static void inject(MotionEvent event) throws Exception {
        event.setSource(InputDevice.SOURCE_TOUCHSCREEN);
        if (!toFilterLooked) {
            toFilterLooked = true;
            try {
                toFilter = UiAutomation.class.getMethod("injectInputEventToInputFilter", InputEvent.class);
            } catch (NoSuchMethodException e) {
                System.out.println("no injectInputEventToInputFilter: plain injection");
            }
        }
        if (toFilter != null) {
            toFilter.invoke(automation, event);
        } else {
            automation.injectInputEvent(event, true);
        }
        event.recycle();
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
