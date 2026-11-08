import com.jpexs.decompiler.flash.SWF;
import com.jpexs.decompiler.flash.exporters.commonshape.Matrix;
import com.jpexs.decompiler.flash.tags.DefineSpriteTag;
import com.jpexs.decompiler.flash.timeline.DepthState;
import com.jpexs.decompiler.flash.timeline.Frame;
import com.jpexs.decompiler.flash.timeline.Timeline;
import com.jpexs.helpers.SerializableImage;
import java.io.File;
import java.io.FileInputStream;
import javax.imageio.ImageIO;

// Renders root frame <rootFrame> with the hall and sky instances forced to the
// given labels, by setting each instance's DepthState.time the way a
// gotoAndStop would have moved its playhead.
public class Probe {
    public static void main(String[] a) throws Exception {
        long t0 = System.nanoTime();
        SWF swf = new SWF(new FileInputStream(a[0]), false);
        long t1 = System.nanoTime();
        int rootFrame = Integer.parseInt(a[1]) - 1;
        Timeline root = swf.getTimeline();
        Frame f = root.getFrame(rootFrame);
        System.out.println("root labels at frame: " + f.labels + " depths: " + f.layers.keySet());
        for (int i = 3; i + 1 < a.length; i += 2) {
            int depth = Integer.parseInt(a[i]);
            String label = a[i + 1];
            DepthState ds = f.layers.get(depth);
            DefineSpriteTag sprite = (DefineSpriteTag) swf.getCharacter(ds.characterId);
            int target = sprite.getTimeline().getFrameWithLabel(label);
            System.out.println("depth " + depth + " cid " + ds.characterId + " name " + ds.instanceName + " label " + label + " -> frame " + (target + 1) + " (time was " + ds.time + ")");
            ds.time = target;
        }
        String keep = System.getProperty("keepDepths");
        if (keep != null) {
            java.util.Set<Integer> k = new java.util.HashSet<>();
            for (String d : keep.split(",")) k.add(Integer.parseInt(d));
            for (var e : f.layers.entrySet()) if (!k.contains(e.getKey())) e.getValue().isVisible = false;
        }
        String hide = System.getProperty("hideCids");
        if (hide != null) {
            java.util.Set<Integer> h = new java.util.HashSet<>();
            for (String c : hide.split(",")) h.add(Integer.parseInt(c));
            int n = 0;
            for (var ch : swf.getCharacters(false).values()) {
                if (!(ch instanceof DefineSpriteTag sp)) continue;
                for (Frame fr : sp.getTimeline().getFrames())
                    for (DepthState ds : fr.layers.values())
                        if (h.contains(ds.characterId)) { ds.isVisible = false; n++; }
            }
            System.out.println("hid " + n + " nested placements");
        }
        SerializableImage img = SWF.frameToImageGet(root, rootFrame, 0, null, 0, swf.displayRect, new Matrix(), null, null, 1.0, true, 1);
        ImageIO.write(img.getBufferedImage(), "png", new File(a[2]));
        long t2 = System.nanoTime();
        System.out.printf("load %.2fs render %.2fs%n", (t1 - t0) / 1e9, (t2 - t1) / 1e9);
    }
}
