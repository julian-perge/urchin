// Renders SWF frames through ffdec's own Java library, with the two overrides
// the ffdec CLI cannot apply: hiding layers the game hides from ActionScript,
// and moving a nested sprite to the frame a gotoAndStop would select.
//
// Run with no build step, as Java's single-file source launcher:
//   java -cp "<jpexs>/dist/lib/*" Render.java job.json
// ffdec_lib.py writes the job and reads the PNGs back. The SWF loads once per
// run and every job in the file renders from it.
//
// Job file:
//   {"swf": path, "jobs": [{
//     "timeline": 0 for the root or a DefineSprite id,
//     "frame": 1-based frame of that timeline,
//     "zoom": 4.0, "out": PNG path, "background": "swf" or "none",
//     "only_depths": [72, 73, 89]          hide every other depth on the frame
//     "hide_depths": [{"owner": id, "depth": d}]  hide a depth on every frame
//     "hide_characters": [2676]            hide every placement of these, in
//                                          every timeline including the root
//     "goto": [{"depth": 89, "label": "CHURCH"}]  move the sprite at that depth
//                                          of the rendered frame to the label
//   }]}
//
// A goto sets the layer's DepthState.time to the label's 0-based frame. A
// child renders frame `time % frameCount` (Timeline.java:1161 at 792d2c2), so
// that is the frame gotoAndStop would have moved its playhead to. Labels match
// case-insensitively, as AVM1 matches them, and the first frame carrying the
// label wins. A missing label fails the job instead of rendering frame 0.
//
// Every override refuses a layer with clipDepth > -1. Timeline.toImage skips an
// invisible layer before it builds that layer's clip, so hiding a mask unclips
// everything under it, the same as stripping one (6622d79).
//
// Overrides are undone after each job, so jobs in one file do not leak into
// each other. Each job prints one JSON line with the canvas size and the
// displayRect it rendered, in twips.
import com.eclipsesource.json.Json;
import com.eclipsesource.json.JsonArray;
import com.eclipsesource.json.JsonObject;
import com.eclipsesource.json.JsonValue;
import com.jpexs.decompiler.flash.SWF;
import com.jpexs.decompiler.flash.exporters.commonshape.Matrix;
import com.jpexs.decompiler.flash.tags.DefineSpriteTag;
import com.jpexs.decompiler.flash.tags.SetBackgroundColorTag;
import com.jpexs.decompiler.flash.tags.base.CharacterTag;
import com.jpexs.decompiler.flash.timeline.DepthState;
import com.jpexs.decompiler.flash.timeline.Frame;
import com.jpexs.decompiler.flash.timeline.Timeline;
import com.jpexs.decompiler.flash.types.RECT;
import com.jpexs.helpers.SerializableImage;
import java.awt.Color;
import java.io.File;
import java.io.FileInputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.IdentityHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import javax.imageio.ImageIO;

public class Render {
    private final SWF swf;
    private final Map<DepthState, boolean[]> savedVisible = new IdentityHashMap<>();
    private final Map<DepthState, int[]> savedTime = new IdentityHashMap<>();

    Render(SWF swf) {
        this.swf = swf;
    }

    public static void main(String[] args) throws Exception {
        JsonObject spec = Json.parse(Files.readString(Path.of(args[0]))).asObject();
        long start = System.nanoTime();
        SWF swf;
        try (FileInputStream in = new FileInputStream(spec.get("swf").asString())) {
            swf = new SWF(in, false);
        }
        System.err.printf("loaded %s in %.2fs%n", spec.get("swf").asString(), (System.nanoTime() - start) / 1e9);
        Render render = new Render(swf);
        for (JsonValue job : spec.get("jobs").asArray()) {
            render.run(job.asObject());
        }
    }

    Timeline timeline(int id) {
        if (id == 0) {
            return swf.getTimeline();
        }
        CharacterTag character = swf.getCharacter(id);
        if (!(character instanceof DefineSpriteTag sprite)) {
            throw new IllegalArgumentException("character " + id + " is not a sprite");
        }
        return sprite.getTimeline();
    }

    List<Timeline> allTimelines() {
        List<Timeline> all = new ArrayList<>();
        all.add(swf.getTimeline());
        for (CharacterTag character : swf.getCharacters(false).values()) {
            if (character instanceof DefineSpriteTag sprite) {
                all.add(sprite.getTimeline());
            }
        }
        return all;
    }

    void hide(DepthState layer, String where) {
        if (layer.clipDepth > -1) {
            throw new IllegalArgumentException("refusing to hide clip mask " + where
                    + " (character " + layer.characterId + ", clipDepth " + layer.clipDepth + ")");
        }
        savedVisible.putIfAbsent(layer, new boolean[] {layer.isVisible});
        layer.isVisible = false;
    }

    static int labelFrame(Timeline child, String label) {
        List<Frame> frames = child.getFrames();
        for (int i = 0; i < frames.size(); i++) {
            for (String name : frames.get(i).labels) {
                if (name.equalsIgnoreCase(label)) {
                    return i;
                }
            }
        }
        return -1;
    }

    void run(JsonObject job) throws Exception {
        long start = System.nanoTime();
        int timelineId = job.getInt("timeline", 0);
        int frameIndex = job.getInt("frame", 1) - 1;
        Timeline tim = timeline(timelineId);
        if (frameIndex < 0 || frameIndex >= tim.getFrameCount()) {
            throw new IllegalArgumentException("timeline " + timelineId + " has no frame " + (frameIndex + 1));
        }
        Frame frame = tim.getFrame(frameIndex);
        String where = "timeline " + timelineId + " frame " + (frameIndex + 1);
        try {
            JsonValue only = job.get("only_depths");
            if (only != null) {
                Set<Integer> keep = new HashSet<>();
                for (JsonValue depth : only.asArray()) {
                    keep.add(depth.asInt());
                }
                for (var entry : frame.layers.entrySet()) {
                    if (!keep.contains(entry.getKey())) {
                        hide(entry.getValue(), where + " depth " + entry.getKey());
                    }
                }
            }
            for (JsonValue value : array(job, "hide_depths")) {
                JsonObject target = value.asObject();
                int owner = target.getInt("owner", 0);
                int depth = target.get("depth").asInt();
                int found = 0;
                List<Frame> frames = timeline(owner).getFrames();
                for (int i = 0; i < frames.size(); i++) {
                    DepthState layer = frames.get(i).layers.get(depth);
                    if (layer != null) {
                        hide(layer, "timeline " + owner + " frame " + (i + 1) + " depth " + depth);
                        found++;
                    }
                }
                if (found == 0) {
                    throw new IllegalArgumentException("timeline " + owner + " has nothing at depth " + depth);
                }
            }
            Set<Integer> hideIds = new HashSet<>();
            for (JsonValue id : array(job, "hide_characters")) {
                hideIds.add(id.asInt());
            }
            if (!hideIds.isEmpty()) {
                Set<Integer> seen = new HashSet<>();
                for (Timeline t : allTimelines()) {
                    List<Frame> frames = t.getFrames();
                    for (int i = 0; i < frames.size(); i++) {
                        for (var entry : frames.get(i).layers.entrySet()) {
                            DepthState layer = entry.getValue();
                            if (hideIds.contains(layer.characterId)) {
                                hide(layer, "timeline " + t.id + " frame " + (i + 1) + " depth " + entry.getKey());
                                seen.add(layer.characterId);
                            }
                        }
                    }
                }
                hideIds.removeAll(seen);
                if (!hideIds.isEmpty()) {
                    throw new IllegalArgumentException("no placement of characters " + hideIds);
                }
            }
            for (JsonValue value : array(job, "goto")) {
                JsonObject target = value.asObject();
                int depth = target.get("depth").asInt();
                String label = target.get("label").asString();
                DepthState layer = frame.layers.get(depth);
                if (layer == null) {
                    throw new IllegalArgumentException(where + " has nothing at depth " + depth);
                }
                Timeline child = timeline(layer.characterId);
                int labelFrame = labelFrame(child, label);
                if (labelFrame < 0) {
                    throw new IllegalArgumentException("sprite " + layer.characterId + " has no label " + label);
                }
                savedTime.putIfAbsent(layer, new int[] {layer.time});
                layer.time = labelFrame;
            }

            Color background = null;
            SetBackgroundColorTag tag = swf.getBackgroundColor();
            if ("swf".equals(job.getString("background", "none")) && tag != null) {
                background = tag.backgroundColor.toColor();
            }
            RECT rect = tim.getDisplayRectWithFilters();
            double zoom = job.getDouble("zoom", 1.0);
            SerializableImage image = SWF.frameToImageGet(tim, frameIndex, 0, null, 0, rect, new Matrix(), null, background, zoom, true, 1);
            File out = new File(job.get("out").asString());
            out.getParentFile().mkdirs();
            ImageIO.write(image.getBufferedImage(), "png", out);
            JsonObject result = new JsonObject()
                    .add("out", out.getPath())
                    .add("width", image.getWidth())
                    .add("height", image.getHeight())
                    .add("xmin", rect.Xmin)
                    .add("ymin", rect.Ymin)
                    .add("xmax", rect.Xmax)
                    .add("ymax", rect.Ymax)
                    .add("seconds", (System.nanoTime() - start) / 1e9);
            System.out.println(result);
        } finally {
            for (var entry : savedVisible.entrySet()) {
                entry.getKey().isVisible = entry.getValue()[0];
            }
            for (var entry : savedTime.entrySet()) {
                entry.getKey().time = entry.getValue()[0];
            }
            savedVisible.clear();
            savedTime.clear();
        }
    }

    static JsonArray array(JsonObject job, String key) {
        JsonValue value = job.get(key);
        return value == null ? new JsonArray() : value.asArray();
    }
}
