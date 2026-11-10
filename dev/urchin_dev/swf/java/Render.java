// Renders SWF frames through ffdec's own Java library, with what the ffdec CLI
// cannot do in one run: delete characters in memory instead of writing a
// stripped copy, hide layers the game hides from ActionScript, and move a
// nested sprite to the frame a gotoAndStop would select.
//
// Run with no build step, as Java's single-file source launcher:
//   java -cp "<jpexs>/dist/lib/*" Render.java job.json
// ffdec_lib.py writes the job and reads the PNGs back. The SWF's bytes are
// read once, and each load parses them again, deletes its characters and
// renders its jobs.
//
// Job file:
//   {"swf": path, "loads": [{
//     "strip_characters": [2676, 3312]     delete these before rendering
//     "jobs": [{
//       "timeline": 0 for the root or a DefineSprite id,
//       "frame": 1-based frame of that timeline,
//       "zoom": 4.0, "out": PNG path, "background": "swf" or "none",
//       "only_depths": [72, 73, 89]        hide every other depth on the frame
//       "hide_depths": [{"owner": id, "depth": d}]  hide a depth on every frame
//       "goto": [{"depth": 89, "label": "CHURCH"}]  move the sprite at that
//                                          depth of the rendered frame to the
//                                          label, or with "frame": 12 in place
//                                          of the label, to that 1-based frame
//     }]
//   }]}
//
// A load deletes its characters the way the CLI's -removeCharacter does, with
// SWF.removeTag, then saves to a buffer and parses that back. Without the
// reparse a timeline keeps the displayRect it had before the delete, so the
// canvas comes out sized for characters that are gone.
//
// A goto sets the layer's DepthState.time to the label's 0-based frame. A
// child renders frame `time % frameCount` (Timeline.java:1161 at 792d2c2), so
// that is the frame gotoAndStop would have moved its playhead to. Labels match
// case-insensitively, as AVM1 matches them, and the first frame carrying the
// label wins. A missing label or a frame past the sprite's last fails the job
// instead of rendering another frame.
//
// Every override and every delete refuses a layer with clipDepth > -1.
// Timeline.toImage skips an invisible layer before it builds that layer's
// clip, so hiding a mask unclips everything under it, the same as stripping
// one (6622d79). strip.py refuses the same ids first.
//
// ffdec draws a sprite with a filter or a blend mode into its own image and then
// composites that image onto its parent. Since jpexs afbe4fa33 ("use outline for
// clipping"), a clip mask inside such a sprite is placed with the absolute matrix,
// which leaves out where that image sits in its parent, so the mask lands off by
// exactly that offset. That cut 51 design px off the left of the biological class
// card and let art through on its right. ClipPlacedTimeline passes each sprite's
// own matrix as the absolute matrix, and the only other readers of that matrix are
// cursor hit tests, which a render here never has.
//
// Overrides are undone after each job, so jobs in one load do not leak into
// each other. Each job prints one JSON line with the canvas size, the rect the
// canvas was sized from (xmin to ymax) and the displayRect without the filter
// margin ("display"), all in twips.
import com.eclipsesource.json.Json;
import com.eclipsesource.json.JsonArray;
import com.eclipsesource.json.JsonObject;
import com.eclipsesource.json.JsonValue;
import com.jpexs.decompiler.flash.SWF;
import com.jpexs.decompiler.flash.configuration.Configuration;
import com.jpexs.decompiler.flash.exporters.commonshape.ExportRectangle;
import com.jpexs.decompiler.flash.exporters.commonshape.Matrix;
import com.jpexs.decompiler.flash.tags.DefineSpriteTag;
import com.jpexs.decompiler.flash.tags.SetBackgroundColorTag;
import com.jpexs.decompiler.flash.tags.base.CharacterTag;
import com.jpexs.decompiler.flash.tags.base.RenderContext;
import com.jpexs.decompiler.flash.timeline.DepthState;
import com.jpexs.decompiler.flash.timeline.Frame;
import com.jpexs.decompiler.flash.timeline.Timeline;
import com.jpexs.decompiler.flash.types.ColorTransform;
import com.jpexs.decompiler.flash.types.RECT;
import com.jpexs.helpers.SerializableImage;
import java.awt.Color;
import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.File;
import java.lang.reflect.Field;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.IdentityHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.TreeSet;
import javax.imageio.ImageIO;

public class Render {
    private final SWF swf;
    private final Map<DepthState, boolean[]> savedVisible = new IdentityHashMap<>();
    private final Map<DepthState, int[]> savedTime = new IdentityHashMap<>();

    Render(SWF swf) {
        this.swf = swf;
    }

    public static void main(String[] args) throws Exception {
        // ffdec narrows a filter's blur box until boxX * boxY * width * height fits
        // under this limit times 100000, so a large filtered object comes out with a
        // thinner blur than the SWF asks for. The largest int means no render here
        // reaches the limit, and setting it in memory leaves ffdec's saved
        // configuration alone.
        Configuration.boxBlurPixelsLimit.set(Integer.MAX_VALUE);
        JsonObject spec = Json.parse(Files.readString(Path.of(args[0]))).asObject();
        byte[] data = Files.readAllBytes(Path.of(spec.get("swf").asString()));
        for (JsonValue value : spec.get("loads").asArray()) {
            JsonObject load = value.asObject();
            long start = System.nanoTime();
            Set<Integer> strip = new TreeSet<>();
            for (JsonValue id : array(load, "strip_characters")) {
                strip.add(id.asInt());
            }
            Render render = new Render(placeClipsOnTheirOwnImage(load(data, strip)));
            System.err.printf("loaded %s without %s in %.2fs%n", spec.get("swf").asString(), strip,
                    (System.nanoTime() - start) / 1e9);
            for (JsonValue job : load.get("jobs").asArray()) {
                render.run(job.asObject());
            }
        }
    }

    static SWF load(byte[] data, Set<Integer> strip) throws Exception {
        SWF swf = new SWF(new ByteArrayInputStream(data), false);
        if (strip.isEmpty()) {
            return swf;
        }
        for (Timeline t : new Render(swf).allTimelines()) {
            List<Frame> frames = t.getFrames();
            for (int i = 0; i < frames.size(); i++) {
                for (var entry : frames.get(i).layers.entrySet()) {
                    DepthState layer = entry.getValue();
                    if (strip.contains(layer.characterId) && layer.clipDepth > -1) {
                        throw new IllegalArgumentException("refusing to strip clip mask " + layer.characterId
                                + " at timeline " + t.id + " frame " + (i + 1) + " depth " + entry.getKey()
                                + " (clipDepth " + layer.clipDepth + ")");
                    }
                }
            }
        }
        for (int id : strip) {
            CharacterTag character = swf.getCharacter(id);
            if (character == null) {
                throw new IllegalArgumentException("no character " + id + " to strip");
            }
            swf.removeTag(character, false, null);
        }
        ByteArrayOutputStream buffer = new ByteArrayOutputStream();
        swf.saveTo(buffer);
        return new SWF(new ByteArrayInputStream(buffer.toByteArray()), false);
    }

    static SWF placeClipsOnTheirOwnImage(SWF swf) throws Exception {
        Field field = DefineSpriteTag.class.getDeclaredField("timeline");
        field.setAccessible(true);
        for (CharacterTag character : swf.getCharacters(false).values()) {
            if (character instanceof DefineSpriteTag sprite) {
                field.set(sprite, new ClipPlacedTimeline(swf, sprite, sprite.getTimeline()));
            }
        }
        return swf;
    }

    static final class ClipPlacedTimeline extends Timeline {
        ClipPlacedTimeline(SWF swf, DefineSpriteTag sprite, Timeline original) {
            super(swf, sprite, original.id, original.displayRect, original.filterDimension);
        }

        @Override
        public void toImage(int frame, int time, RenderContext renderContext, SerializableImage image,
                SerializableImage fullImage, boolean isClip, Matrix transformation, Matrix strokeTransformation,
                Matrix absoluteTransformation, ColorTransform colorTransform, double unzoom, boolean sameImage,
                ExportRectangle viewRect, ExportRectangle viewRectRaw, Matrix fullTransformation, boolean scaleStrokes,
                int drawMode, int blendMode, boolean canUseSmoothing, List<Integer> ignoreDepths, int aaScale) {
            super.toImage(frame, time, renderContext, image, fullImage, isClip, transformation, strokeTransformation,
                    transformation, colorTransform, unzoom, sameImage, viewRect, viewRectRaw, fullTransformation,
                    scaleStrokes, drawMode, blendMode, canUseSmoothing, ignoreDepths, aaScale);
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
        int frameIndex = job.get("frame").asInt() - 1;
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
            for (JsonValue value : array(job, "goto")) {
                JsonObject target = value.asObject();
                int depth = target.get("depth").asInt();
                DepthState layer = frame.layers.get(depth);
                if (layer == null) {
                    throw new IllegalArgumentException(where + " has nothing at depth " + depth);
                }
                Timeline child = timeline(layer.characterId);
                int time;
                if (target.get("frame") != null) {
                    time = target.get("frame").asInt() - 1;
                    if (time < 0 || time >= child.getFrameCount()) {
                        throw new IllegalArgumentException("sprite " + layer.characterId + " has no frame " + (time + 1));
                    }
                } else {
                    String label = target.get("label").asString();
                    time = labelFrame(child, label);
                    if (time < 0) {
                        throw new IllegalArgumentException("sprite " + layer.characterId + " has no label " + label);
                    }
                }
                savedTime.putIfAbsent(layer, new int[] {layer.time});
                layer.time = time;
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
            RECT display = tim.displayRect;
            JsonObject result = new JsonObject()
                    .add("out", out.getPath())
                    .add("width", image.getWidth())
                    .add("height", image.getHeight())
                    .add("xmin", rect.Xmin)
                    .add("ymin", rect.Ymin)
                    .add("xmax", rect.Xmax)
                    .add("ymax", rect.Ymax)
                    .add("display", Json.array(display.Xmin, display.Ymin, display.Xmax, display.Ymax))
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
