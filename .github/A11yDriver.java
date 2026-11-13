// emu-lib: tools/emu/A11yDriver.java sha a1d9b259d646 - edit there, then tools/emu/sync.py (T-505)
// Test only (T-222, T-487; one source since T-505: tools/emu/A11yDriver.java of the work folder, copied
// into .github/ of a branch by tools/emu/sync.py): send the app the accessibility actions TalkBack sends,
// without TalkBack (or with it on, see --keep; the image has Google TalkBack 15). Runs through app_process
// as the shell, with the UiAutomation connection uiautomator uses, so only one may run at a time
// and no dump meanwhile.
//
//   CLASSPATH=/data/local/tmp/a11y.jar app_process / A11yDriver [--keep] step [step ...]
//   step: list | sleep:<ms> | find:<desc> | focus:<desc> | click:<desc> | fwd:<desc> | back:<desc>
//         | swipe:right|left|up|down | dtap | touch:<desc> | touchat:<x>,<y> | focused | mark:<text>
//         | click=<name> | fwd@<x>,<y> | drag@<x>,<y1>,<y2>
// touchat: a resting finger at a point, for a node with no description in the tree.
// <desc> is the start of a content description; the first node in tree order that matches is used.
// click=<name>: ACTION_CLICK on the one node on the screen whose content description or text is exactly
// <name> (lib.sh tap_ui --a11y); none - "NOT FOUND", two or more - "AMBIGUOUS", no click.
// --keep: connect without switching the other accessibility services off, for a run with the
// real TalkBack; then the gesture steps go to its touch explorer, as a finger would, and after
// each gesture the text of TalkBack's speech overlay (its "display speech output") is printed
// as "said:", with a screenshot in /data/local/tmp/tbshots.
import android.os.HandlerThread;
import android.os.Looper;
import android.os.SystemClock;
import android.util.Log;
import android.view.InputDevice;
import android.view.InputEvent;
import android.view.MotionEvent;
import android.accessibilityservice.AccessibilityServiceInfo;
import android.app.UiAutomation;
import android.graphics.Bitmap;
import android.view.accessibility.AccessibilityWindowInfo;
import java.io.FileOutputStream;
import java.util.LinkedHashSet;
import java.util.List;
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
            AccessibilityServiceInfo info = automation.getServiceInfo();
            info.flags |= AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS
                    | AccessibilityServiceInfo.FLAG_INCLUDE_NOT_IMPORTANT_VIEWS;
            automation.setServiceInfo(info);
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
        if (step.startsWith("click=")) {
            clickExact(step, step.substring("click=".length()));
            return;
        }
        if (step.startsWith("fwd@")) {
            forwardAt(step, step.substring("fwd@".length()));
            return;
        }
        if (step.startsWith("drag@")) {
            drag(step, step.substring("drag@".length()));
            return;
        }
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
            listen(step, 2500);
            printFocused(step);
            return;
        }
        if (verb.equals("dtap")) {
            Log.i("A11yDriver", step);
            stroke(720, 1300, 720, 1300, 50);
            Thread.sleep(80);
            stroke(720, 1300, 720, 1300, 50);
            listen(step, 2500);
            printFocused(step);
            return;
        }
        if (verb.equals("focused")) {
            printFocused(step);
            return;
        }
        if (verb.equals("touchat")) {
            // touch exploration at a point: for a row with no name in the tree (T-514: the classic
            // program rows - an empty delegate text, the name Text not in the tree)
            int comma = arg.indexOf(',');
            int x = Integer.parseInt(arg.substring(0, comma).trim());
            int y = Integer.parseInt(arg.substring(comma + 1).trim());
            Log.i("A11yDriver", step);
            System.out.println(step + ": at " + x + "," + y);
            stroke(x, y, x + 4, y + 4, 600);
            listen(step, 2500);
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
            listen(step, 2500);
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

    // What TalkBack shows of its speech during ms, and a screenshot 400 ms in
    private static void listen(String step, long ms) throws Exception {
        LinkedHashSet<String> said = new LinkedHashSet<>();
        long start = SystemClock.uptimeMillis();
        boolean shot = false;
        while (SystemClock.uptimeMillis() - start < ms) {
            if (!shot && SystemClock.uptimeMillis() - start >= 400) {
                shot = true;
                screenshot(step);
            }
            List<AccessibilityWindowInfo> windows = automation.getWindows();
            for (AccessibilityWindowInfo window : windows) {
                AccessibilityNodeInfo root = window.getRoot();
                if (root != null && root.getPackageName() != null
                        && root.getPackageName().toString().contains("talkback")) {
                    texts(root, said);
                }
            }
            Thread.sleep(80);
        }
        System.out.println(step + ": said " + said);
        Log.i("A11yDriver", step + ": said " + said);
    }

    private static void texts(AccessibilityNodeInfo node, LinkedHashSet<String> out) {
        if (node == null) {
            return;
        }
        if (node.getText() != null && node.getText().length() > 0) {
            out.add(node.getText().toString());
        }
        if (node.getContentDescription() != null && node.getContentDescription().length() > 0) {
            out.add(node.getContentDescription().toString());
        }
        for (int i = 0; i < node.getChildCount(); i++) {
            texts(node.getChild(i), out);
        }
    }

    private static void screenshot(String step) {
        try {
            Bitmap bitmap = automation.takeScreenshot();
            if (bitmap == null) {
                return;
            }
            String name = String.format("/data/local/tmp/tbshots/%d-%s.png", SystemClock.uptimeMillis(),
                    step.replaceAll("[^A-Za-z0-9]+", "_"));
            FileOutputStream out = new FileOutputStream(name);
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, out);
            out.close();
        } catch (Exception e) {
            System.out.println("screenshot: " + e);
        }
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

    // drag@<x>,<y1>,<y2>: one finger from y1 to y2 at x the way UiAutomator swipes - all events from this one
    // process (lib.sh swipe_page … exact, T-505). Still 250 ms, one jump of 60 px past the drag threshold
    // and 200 ms still - the part of the way Flickable does not go (dragStartOffset,
    // qquickflickable.cpp:1130-1137 v5.15.0) is that jump every time (why - inside); then a move every 5 ms
    // by at most 10 px (`input motionevent`, a process per event, gave the first move 0.3-1 s late and
    // 370 px long). Then the finger stands 300 ms: Flickable flicks only when the last move is less than 100 ms before the release
    // (:1348-1367). Straight to the input system, not to TalkBack's filter: a drag of the page, not a gesture
    private static void drag(String step, String args) throws Exception {
        String[] p = args.split(",");
        if (p.length != 3) {
            System.out.println(step + ": BAD ARGS");
            return;
        }
        int x = Integer.parseInt(p[0].trim());
        int y1 = Integer.parseInt(p[1].trim());
        int y2 = Integer.parseInt(p[2].trim());
        long down = SystemClock.uptimeMillis();
        plain(MotionEvent.obtain(down, down, MotionEvent.ACTION_DOWN, x, y1, 0));
        // Repeatable run by run. QQuickWindow joins the touch updates of one frame (compressTouchEvent,
        // qquickwindow.cpp:2169-2229 v5.15.0; a frame of the CI emulator may be longer than 30 ms), so the
        // move that crosses the drag threshold must come alone: 250 ms still (Flickable takes the first
        // move after 200 ms into dragStartOffset, qquickflickable.cpp:1130-1137), one jump of JUMP px - past
        // the threshold, the same offset each time - and 200 ms still; then fast, the page follows the last
        // point. Every 5 ms from the press the page moved +-30 px per swipe, up to 360 px by the 8th screen;
        // the first 200 px one move per 30 ms - still up to 70 px (T-505 pilots 10-13)
        final int JUMP = 60;
        int dir = y2 >= y1 ? 1 : -1;
        int y0 = Math.abs(y2 - y1) > JUMP ? y1 + dir * JUMP : y2;
        Thread.sleep(250);
        plain(MotionEvent.obtain(down, SystemClock.uptimeMillis(), MotionEvent.ACTION_MOVE, x, y0, 0));
        Thread.sleep(200);
        int moves = 1 + Math.max(0, (Math.abs(y2 - y0) + 9) / 10);
        for (int i = 1; i < moves; i++) {
            Thread.sleep(5);
            float y = y0 + (y2 - y0) * i / (float) (moves - 1);
            plain(MotionEvent.obtain(down, SystemClock.uptimeMillis(), MotionEvent.ACTION_MOVE, x, y, 0));
        }
        Thread.sleep(300);
        plain(MotionEvent.obtain(down, SystemClock.uptimeMillis(), MotionEvent.ACTION_UP, x, y2, 0));
        System.out.println(step + ": done (" + moves + " moves)");
    }

    private static void plain(MotionEvent event) {
        event.setSource(InputDevice.SOURCE_TOUCHSCREEN);
        automation.injectInputEvent(event, true);
        event.recycle();
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

    // click=<name>: the exact name, only nodes on the screen, refused when not one
    // fwd@<x>,<y>: ACTION_SCROLL_FORWARD on the deepest node on the screen at that point that has the
    // action (a node without a name: the scroll bar of a page); answers at once, as click= does, so the
    // next step - or the disconnect at the end - follows right away (T-508: the app's delayed work after
    // the action must survive accessibility going off)
    private static void forwardAt(String step, String point) throws Exception {
        int comma = point.indexOf(',');
        int x = Integer.parseInt(point.substring(0, comma).trim());
        int y = Integer.parseInt(point.substring(comma + 1).trim());
        AccessibilityNodeInfo node = deepestScrollable(automation.getRootInActiveWindow(), x, y);
        if (node == null) {
            System.out.println(step + ": NOT FOUND");
            return;
        }
        System.out.println(step + ": before " + describe(node));
        boolean result = node.performAction(AccessibilityNodeInfo.ACTION_SCROLL_FORWARD);
        Log.i("A11yDriver", step + " returned " + result);
        System.out.println(step + ": returned " + result);
    }

    private static AccessibilityNodeInfo deepestScrollable(AccessibilityNodeInfo node, int x, int y) {
        if (node == null || !node.isVisibleToUser()) {
            return null;
        }
        Rect bounds = new Rect();
        node.getBoundsInScreen(bounds);
        if (!bounds.contains(x, y)) {
            return null;
        }
        for (int i = node.getChildCount() - 1; i >= 0; i--) {
            AccessibilityNodeInfo found = deepestScrollable(node.getChild(i), x, y);
            if (found != null) {
                return found;
            }
        }
        for (AccessibilityNodeInfo.AccessibilityAction a : node.getActionList()) {
            if (a.getId() == AccessibilityNodeInfo.ACTION_SCROLL_FORWARD) {
                return node;
            }
        }
        return null;
    }

    private static void clickExact(String step, String name) throws Exception {
        java.util.ArrayList<AccessibilityNodeInfo> found = new java.util.ArrayList<>();
        exact(automation.getRootInActiveWindow(), name, found);
        if (found.isEmpty()) {
            System.out.println(step + ": NOT FOUND");
            return;
        }
        if (found.size() > 1) {
            System.out.println(step + ": AMBIGUOUS " + found.size());
            for (AccessibilityNodeInfo n : found) {
                System.out.println(step + ":   " + describe(n));
            }
            return;
        }
        AccessibilityNodeInfo node = found.get(0);
        System.out.println(step + ": before " + describe(node));
        boolean result = node.performAction(AccessibilityNodeInfo.ACTION_CLICK);
        Log.i("A11yDriver", step + " returned " + result);
        System.out.println(step + ": returned " + result);
    }

    private static void exact(AccessibilityNodeInfo node, String name, java.util.List<AccessibilityNodeInfo> out) {
        if (node == null) {
            return;
        }
        CharSequence desc = node.getContentDescription();
        CharSequence text = node.getText();
        boolean named = (desc != null && desc.toString().trim().equals(name))
                || (text != null && text.toString().trim().equals(name));
        if (named && node.isVisibleToUser()) {
            // the label inside its own control (the same name on the item and its text) is one control
            boolean inner = false;
            for (AccessibilityNodeInfo o : out) {
                Rect a = new Rect();
                Rect b = new Rect();
                o.getBoundsInScreen(a);
                node.getBoundsInScreen(b);
                if (a.contains(b)) {
                    inner = true;
                    break;
                }
            }
            if (!inner) {
                out.add(node);
            }
        }
        for (int i = 0; i < node.getChildCount(); i++) {
            exact(node.getChild(i), name, out);
        }
    }

    private static AccessibilityNodeInfo find(AccessibilityNodeInfo node, String start) {
        if (node == null) {
            return null;
        }
        CharSequence desc = node.getContentDescription();
        // only a node on the screen: a hidden page keeps its nodes (the home tile "Speed (km/h): 0.0")
        if (desc != null && node.isVisibleToUser() && desc.toString().startsWith(start)) {
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
