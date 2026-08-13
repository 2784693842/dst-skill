stdout (49717 chars):
# Lua Scripting API Guide

Lua scripts can read and modify the current animation document. They are useful for batch renaming, reorganizing hierarchies, editing animations, replacing images, and performing complex Element operations.

Use the global `doc` object to access the document and `tool` to read the Animation Tool state:

```lua
print("Builds:", #doc.builds)
print("Banks:", #doc.banks)
print("Revision:", tool.document_revision)
print("Empty document:", tool.document_is_empty)
```

## Execution Rules

- When a script is run from the in-app editor, the editor saves the script file before running it. External
  `--file`, `--text`, and `--stdin` requests execute their supplied source and do not rewrite the source file.
- All Document edits made through `doc` and node APIs in one successful run appear as one operation in
  undo history.
- Changes made by an earlier statement are immediately visible to later statements.
- If the script has a syntax error, runtime error, or exceeds a resource limit, none of its changes are applied.
- A read-only script does not create an undo entry.
- `tool` starts from captured App state. Selection, playback, History, Hide Layer, and Override Symbol
  commands immediately update a worker-side projection, so later statements observe those calls.
- `tool` operations and image exports are queued, then run in call order only after Lua and the Document commit succeed.
- `print(...)` joins arguments with tabs and appends the line to the output panel.

If a deferred `tool` operation fails, later deferred operations are not executed. A Document change that
was already committed and earlier `tool` operations that already completed are not rolled back. External
callers must inspect `ok`, `error`, and `tool_results` in the execution report instead of checking only the
Document revision.

## Basic Conventions

### Collections

All collections are ordered, 1-based sequences that support `ipairs` and the length operator:

```lua
for i, build in ipairs(doc.builds) do
    print(i, build.name)
end
```

An out-of-range index returns `nil`. Collections are read-only views, so `collection[i] = value` is not allowed. Use `add`, `remove`, `move_to`, or `move_to_parent` instead.

Document collections do not support `pairs`. Use `ipairs` to preserve document order, and use a numeric
index loop when removing or moving items in reverse order. Ordinary Lua tables such as
`tool.override_symbols` still support `pairs`.

Name-based `find(name)` calls are case-insensitive. `SymbolFrame` collections use `find(num)` for an exact Frame `num` lookup.

### Fields and Methods

Every Build, Symbol, SymbolFrame, Bank, Animation, AnimFrame, and Element exposes a read-only `id`
as a decimal string. The ID is stable within the current DMT document across edits, reordering,
save/load, and undo/redo; clones and newly created nodes receive new IDs. Formats such as
`build.bin`, `anim.bin`, SCML, and Spine do not preserve these IDs across export and re-import.

Writable fields support both direct assignment and explicit setter methods:

```lua
print(animation.frame_rate)
animation.frame_rate = 30
animation:set_frame_rate(30)
```

Direct assignment is convenient for one field. Explicit setters return `true` when a value changed and `false` when it was already equal; `set_pivot`, `set_bounds`, `set_reference`, and `set_transform` also update related fields together. Both forms use the same validation and belong to the same undo entry.

Read-only fields, child collections, and document structure cannot be assigned. Use `add`, `remove`, `move_to`, or `move_to_parent` for structural edits. `clone()` returns the new copy, and `add()` returns the newly created object.

### Removal and Iteration

After `remove()` succeeds, the old object is no longer valid. Do not read it or call another method on it. Remove items from the end when mutating a collection during iteration:

```lua
for i = #animation.frames, 1, -1 do
    animation.frames[i]:remove()
end
```

### Ordering

`move_to(index)` uses a 1-based target position and does not wrap around.

Symbol order is managed by name, and Symbol Frame order is managed by `num`, so these objects do not expose `move_to`. Renaming a Symbol or changing a Frame `num` may change its collection position. Keep the object in a local variable or call `find` again when needed.

## Document Hierarchy

```text
doc
âââ builds
â   âââ Build
â       âââ symbols
â           âââ Symbol
â               âââ frames
â                   âââ SymbolFrame
âââ banks
    âââ Bank
        âââ animations
            âââ Animation
                âââ frames
                    âââ AnimFrame
                        âââ elements
                            âââ Element
```

## `tool`

`tool` reads Animation Tool session state and invokes non-Document operations. Its fields start from a
snapshot captured when the script starts. Selection, playback, History, Hide Layer, Override Symbol,
and the bound DMT path are updated in a local projection as commands are queued, so later Lua statements
can read those projected values. App side effects still run in call order after the Document transaction
commits. If a host command fails, later commands are skipped. The IPC report includes
`final_tool_state` only when the run queued a command whose real App state needs confirmation
(selection/playback, preview rules, History, `open_document`, or `save_document_as`); otherwise the
field is omitted.

| Field | Type | Description |
| --- | --- | --- |
| `document_revision` | integer | Document revision when the script started |
| `document_is_empty` | boolean | Whether the Document contained no Builds or Banks when the script started |
| `document_path` | string or `nil` | The currently bound absolute `.dmt` path |
| `selection` | table | Primary selection, initially captured at script start and then updated by queued selection commands; contains available `bank`, `animation`, `frame`, and `element` handles, with absent selections represented by `nil` |
| `playback` | table | Playback state, initially captured at script start and then updated by queued selection/playback commands; contains `playing`, `looping`, `frame_index`, `frame_count`, and `fps` |
| `history` | table | History state, initially captured at script start and then updated by queued `undo`/`redo`; contains `entries`, `cursor`, `can_undo`, and `can_redo` |
| `hide_layers` | string[] | Enabled Hide Layer names, initially captured at script start and then updated by queued preview commands; sorted by name |
| `override_symbols` | table | Enabled Override Symbol map, initially captured at script start and then updated by queued preview commands, from source Symbol to replacement Symbol |

| Method | Description |
| --- | --- |
| `tool:select_animation(animation)` | Exclusively select an Animation after the script commits; the argument must be an Animation handle from the current `doc` |
| `tool:select_frame(frame)` | Exclusively select an Anim Frame and its owning Bank/Animation after the script commits, then seek to it; seeking pauses playback automatically |
| `tool:play()` | Play the current Animation after the script commits; if its Scene is still preparing, playback starts when it becomes ready |
| `tool:pause()` | Pause the current Animation after the script commits |
| `tool:undo(steps?)` | Undo the requested number of steps after the script succeeds; defaults to `1`, `0` is a no-op, and excess steps are silently clamped |
| `tool:redo(steps?)` | Redo the requested number of steps after the script succeeds; defaults to `1`, `0` is a no-op, and excess steps are silently clamped |
| `tool:set_hide_layer(layer, enabled)` | Enable or disable a Hide Layer by name after the script succeeds |
| `tool:set_override_symbol(source, target?)` | Set an Override Symbol after the script succeeds; omit `target` or pass `nil` to clear the source override |
| `tool:save_document()` | Save the committed Document to its existing `.dmt` binding |
| `tool:save_document_as(absolute_path)` | Atomically save the committed Document and bind the workspace to that `.dmt` path |
| `tool:open_document(absolute_path)` | Replace the workspace with a `.dmt` file; this is a terminal command |

`steps` must be a non-negative integer. `undo` / `redo` cannot be mixed with Document changes in the same script run. A conflict fails the whole run without applying Document changes or queued tool commands, even if Lua catches the immediate error with `pcall`.

`history.entries` is a chronological, 1-based sequence of operation labels. `history.cursor` is the number of operations applied from the beginning of the timeline, in the range `0..#history.entries`; entries after the cursor are in the redo region. History queries never expose internal Transactions or Patches.

An Animation or Anim Frame created by the same script can be selected
because the host commits the Document before executing commands in call order:

```lua
local bank = doc.banks:find("wilson")
local animation = bank and bank.animations:find("idle_loop")
if animation then
    tool:select_animation(animation)
    tool:select_frame(animation.frames[1])
    tool:play()
end
```

`frame_index` is zero-based. `select_frame` accepts a 1-based Anim Frame handle rather than a numeric
index. It reuses the same selection and seek path as clicking a frame in the UI, so it pauses playback
and updates the list, inspector, and viewport. Within the same run, `tool.selection` and `tool.playback`
reflect queued selection and playback commands. When present, `final_tool_state` is the authoritative App
state after the deferred commands finish. Playback commands require a selected Animation with at least one
frame when they execute; otherwise they return a `tool_command` error.

```lua
for _, layer in ipairs(tool.hide_layers) do
    print("hidden layer", layer)
end

tool:set_hide_layer("arm_normal", true)
tool:set_override_symbol("swap_object", "swap_axe")
tool:set_override_symbol("snow", nil) -- clear the override
```

Commands execute in script order, so an Animation or AnimFrame image export queued after these
updates uses the updated preview rules. Hide Layers and Override Symbols are workspace preview state;
they do not modify the Document or create History entries.

## `doc`

### Fields

| Field | Type | Description |
| --- | --- | --- |
| `builds` | Build collection | All Builds in the current document |
| `banks` | Bank collection | All Banks in the current document |

### Methods

| Method | Description |
| --- | --- |
| `doc:set_label(label)` | Set the name shown in operation history after this script commits successfully; the last call wins |
| `doc:import_resources(paths, options?)` | Import animation resources from absolute paths and return sequences of newly added `builds` and `banks` handles |
| `doc:search_replace_elements(scope, rule)` | Batch find, replace, or remove Elements in a scope; returns `true` on success |
| `doc:recalculate_collision(scope, options)` | Recalculate Anim Frame collision bounds using selected Builds; returns `true` on success |

`set_label` does not modify the document or consume a mutation operation. Calling only `set_label` without making a document change does not create an empty undo entry.

`import_resources` supports ZIP, DYN, BIN, SCML, GIF, PNG, Spine JSON, and PSD. Multiple PNG paths are combined into one image sequence using the normal animation import rules. Directories are not scanned, and `.dmt` files are rejected. The import and all later changes in the run share one transaction, so returned handles can be edited immediately:

```lua
local imported = doc:import_resources({
    [[C:\assets\character.zip]],
    [[C:\assets\effect.psd]],
}, {
    spine_colors = "bake", -- or "ignore"
    spine_color_tolerance = 0.1,
})

for _, bank in ipairs(imported.banks) do
    bank.name = "imported_" .. bank.name
end
```

Paths must be absolute. `spine_color_tolerance` must be in `0..1`, and unknown option fields are rejected. When Spine uses bakeable slot colors and the application preference is set to ask every time, the script must provide `spine_colors`; scripts never open an interactive prompt. Parse failures, empty imports, and later Lua errors discard the whole run.

## Build Tree API

### Build Collection

| API | Returns | Description |
| --- | --- | --- |
| `#doc.builds` | integer | Number of Builds |
| `doc.builds[index]` | Build or `nil` | Read a Build by order |
| `doc.builds:find(name)` | Build or `nil` | Case-insensitive name lookup |
| `doc.builds:add(name)` | Build | Append a Build; a new Build includes one default Symbol and Symbol Frame |

### Build

Fields:

| Field | Type | Writable | Description |
| --- | --- | --- | --- |
| `name` | string | Yes | Build name |
| `version` | integer | No | Build version |
| `hidden` | boolean | Yes | Hidden state |
| `symbols` | Symbol collection | No | Child Symbols |

Methods:

| API | Returns | Description |
| --- | --- | --- |
| `build:set_name(name)` | boolean | Change the name |
| `build:set_hidden(hidden)` | boolean | Change the hidden state |
| `build:clone()` | Build | Copy the Build and return the copy |
| `build:move_to(index)` | boolean | Move to a position in the Build collection |
| `build:remove_unused_symbols()` | boolean | Remove unused Symbols from this Build |
| `build:remove()` | boolean | Remove the Build |

### Symbol Collection

| API | Returns | Description |
| --- | --- | --- |
| `#build.symbols` | integer | Number of Symbols |
| `build.symbols[index]` | Symbol or `nil` | Read a Symbol by current order |
| `build.symbols:find(name)` | Symbol or `nil` | Case-insensitive name lookup |
| `build.symbols:add(name)` | Symbol | Create a Symbol with one default Symbol Frame |

### Symbol

Writable fields: `name` and `hidden`. Read-only field: `frames`.

| API | Returns | Description |
| --- | --- | --- |
| `symbol:set_name(name)` | boolean | Change the name |
| `symbol:set_hidden(hidden)` | boolean | Change the hidden state |
| `symbol:clone()` | Symbol | Copy the Symbol and return the copy |
| `symbol:move_to_parent(build)` | boolean | Move to the end of another Build |
| `symbol:remove_unused_frames()` | boolean | Remove unused Symbol Frames from this Symbol |
| `symbol:remove()` | boolean | Remove the Symbol |

### Symbol Frame Collection

| API | Returns | Description |
| --- | --- | --- |
| `#symbol.frames` | integer | Number of Symbol Frames |
| `symbol.frames[index]` | SymbolFrame or `nil` | Read a Symbol Frame by current order |
| `symbol.frames:find(num)` | SymbolFrame or `nil` | Find the Frame with an exact `num` |
| `symbol.frames:add(num)` | SymbolFrame | Create a Symbol Frame with the given `num` |

### SymbolFrame

Fields:

| Field | Type | Writable | Description |
| --- | --- | --- | --- |
| `num` | integer | Yes | Frame number |
| `duration` | integer | Yes | Duration |
| `pivot_x` | number | Yes | Pivot X |
| `pivot_y` | number | Yes | Pivot Y |
| `width` | number | No | Image width; changed only by replacing the image |
| `height` | number | No | Image height; changed only by replacing the image |
| `hidden` | boolean | Yes | Hidden state |

Methods:

| API | Returns | Description |
| --- | --- | --- |
| `frame:set_num(num)` | boolean | Set the Frame number to a non-negative integer |
| `frame:set_duration(duration)` | boolean | Set the duration to an integer of at least `1` |
| `frame:set_pivot(x, y)` | boolean | Set a finite Pivot; Animation is not adjusted automatically |
| `frame:set_hidden(hidden)` | boolean | Change the hidden state |
| `frame:replace_image(absolute_path)` | boolean | Replace the image from an absolute path |
| `frame:export_png(absolute_png_path)` | nil | Render this Symbol Frame to the exact PNG path without resizing |
| `frame:clone()` | SymbolFrame | Copy the Symbol Frame and return the copy |
| `frame:move_to_parent(symbol)` | boolean | Move the Symbol Frame to another Symbol |
| `frame:remove()` | boolean | Remove the Symbol Frame |

Image replacement accepts any absolute path that the application can read. Symbol Frame export preserves the Frame's raster size; FrameImage sources pass through directly, while Atlas and Mesh sources are rendered from their geometry. A later Lua error prevents the queued export from running. The new `width` and `height` after replacement are available immediately:

```lua
local build = assert(doc.builds:find("wilson"), "Build not found")
local symbol = assert(build.symbols:find("body"), "Symbol not found")
local frame = assert(symbol.frames:find(0), "Symbol Frame not found")

frame:replace_image([[/Users/name/assets/body.png]])
print(frame.width, frame.height)
```

Use a Lua long string for Windows paths to avoid backslash escaping:

```lua
frame:replace_image([[C:\assets\body.png]])
```

## Bank Tree API

### Bank Collection

| API | Returns | Description |
| --- | --- | --- |
| `#doc.banks` | integer | Number of Banks |
| `doc.banks[index]` | Bank or `nil` | Read a Bank by order |
| `doc.banks:find(name)` | Bank or `nil` | Case-insensitive name lookup |
| `doc.banks:add(name)` | Bank | Append a Bank with a default Animation, Anim Frame, and Element |

### Bank

Writable field: `name`. Read-only field: `animations`.

| API | Returns | Description |
| --- | --- | --- |
| `bank:set_name(name)` | boolean | Change the name |
| `bank:clone()` | Bank | Copy the Bank and return the copy |
| `bank:move_to(index)` | boolean | Move to a position in the Bank collection |
| `bank:transform(transform)` | boolean | Apply a transform to the Bank's animations |
| `bank:anti_follow(options)` | boolean | Run Anti-Follow Symbol on the Bank's Animations |
| `bank:remove()` | boolean | Remove the Bank |

### Animation Collection

| API | Returns | Description |
| --- | --- | --- |
| `#bank.animations` | integer | Number of Animations |
| `bank.animations[index]` | Animation or `nil` | Read an Animation by order |
| `bank.animations:find(name)` | Animation or `nil` | Case-insensitive name lookup |
| `bank.animations:add(name)` | Animation | Create an Animation with a default Anim Frame and Element |

### Animation

Writable fields: `name` and `frame_rate`. Read-only field: `frames`.

| API | Returns | Description |
| --- | --- | --- |
| `animation:set_name(name)` | boolean | Change the name |
| `animation:set_frame_rate(rate)` | boolean | Set a finite frame rate greater than `0` |
| `animation:clone()` | Animation | Copy the Animation and return the copy |
| `animation:move_to(index)` | boolean | Move within the current Bank |
| `animation:move_to_parent(bank)` | boolean | Move to the end of another Bank |
| `animation:reverse()` | boolean | Reverse the Anim Frame order |
| `animation:append(source)` | boolean | Append copies of `source` Anim Frames; `source` is unchanged |
| `animation:transform(transform)` | boolean | Apply a transform to the Animation |
| `animation:anti_follow(options)` | boolean | Run Anti-Follow Symbol |
| `animation:follow_symbol(child, options)` | boolean | Attach `child` Animation to matching Symbols |
| `animation:crop(points)` | Animation[] | Split into 2 to 4 copied Animations at 1 to 3 zero-based frame boundaries; the original Animation remains |
| `animation:compare_transition(other, options?)` | table | Compare this Animation's final frame with another Animation's first frame or selected frame indexes |
| `animation:export_png_sequence(absolute_directory, options?)` | nil | Render every Anim Frame as a numbered PNG sequence |
| `animation:export_gif(absolute_gif_path, options?)` | nil | Render every Anim Frame to one GIF file |
| `animation:export_apng(absolute_png_path, options?)` | nil | Render every Anim Frame to one APNG file |
| `animation:remove()` | boolean | Remove the Animation |

### Anim Frame Collection

| API | Returns | Description |
| --- | --- | --- |
| `#animation.frames` | integer | Number of Anim Frames |
| `animation.frames[index]` | AnimFrame or `nil` | Read an Anim Frame by order |
| `animation.frames:add()` | AnimFrame | Append an Anim Frame with a default Element |

### AnimFrame

Writable fields: `x`, `y`, `width`, and `height`. Read-only field: `elements`.

| API | Returns | Description |
| --- | --- | --- |
| `anim_frame:set_bounds(x, y, width, height)` | boolean | Set collision bounds; all four values must be finite |
| `anim_frame:export_png(absolute_png_path, options?)` | nil | Render this Anim Frame to the exact PNG path |
| `anim_frame:clone()` | AnimFrame | Copy the Anim Frame and return the copy |
| `anim_frame:move_to(index)` | boolean | Move within the current Animation |
| `anim_frame:move_to_parent(animation)` | boolean | Move to the end of another Animation |
| `anim_frame:transform(transform)` | boolean | Apply a transform to the Frame's Elements |
| `anim_frame:remove()` | boolean | Remove the Anim Frame |

Animation image exports freeze their render policy when Lua calls them. By default they use the visible
Builds and active Layer/Symbol preview rules observed at that point in the script. `builds`,
`hide_layers`, `override_symbols`, `background`, and `canvas` replace those defaults for that one
export only; they never modify the workspace preview. When supplied explicitly, `builds` must be an
ordered, non-empty array of unique Build handles. Symbol and Layer comparisons are case-insensitive but
preserve leading and trailing spaces.

The optional resize table accepts either `{ scale = number }` or `{ max_dimension = integer }`, never
both; unknown fields are rejected. `scale` must be finite and greater than zero; `max_dimension` must
be positive. `background` is either omitted for transparent output or `{ r = 0..255, g = 0..255,
b = 0..255 }`. `canvas` fixes the render area with `{ center_x, center_y, width, height }`; each edge
must be in `1..4096`. Omit `canvas` to use the union of the Animation's frame bounds. The renderer
also rejects original or resized edges above 4096 pixels.

```lua
animation.frames[1]:export_png([[/absolute/output/first.png]], {
    scale = 0.5,
})
animation:export_png_sequence([[/absolute/output/idle-frames]], {
    builds = { doc.builds[1] },
    hide_layers = { "shadow" },
    override_symbols = { swap_object = "swap_spear" },
    background = { r = 48, g = 48, b = 48 },
    canvas = { center_x = 0, center_y = -40, width = 1024, height = 1024 },
    max_dimension = 1024,
})
animation:export_gif([[/absolute/output/idle.gif]])
animation:export_apng([[/absolute/output/idle.png]])
```

The PNG, GIF, and APNG paths are replaced atomically. A sequence export requires a target directory
that does not already exist, creates it atomically, and writes deterministic names such as `0000.png`.
Export commands run in script call order after all Document changes commit. If Lua fails before that
point, no export is written.

### Element Collection

| API | Returns | Description |
| --- | --- | --- |
| `#anim_frame.elements` | integer | Number of Elements |
| `anim_frame.elements[index]` | Element or `nil` | Read an Element by draw order |
| `anim_frame.elements:add(fields)` | Element | Append an Element |
| `anim_frame.elements:update_many(updates)` | boolean | Atomically update several Elements in this Frame |
| `anim_frame.elements:transform_all(transform)` | boolean | Apply one transform to every Element in this Frame |

`add(fields)` requires `symbol`, `frame`, and `layer`. Transform fields are optional and default to the identity transform:

```lua
local element = anim_frame.elements:add({
    symbol = "body",
    frame = 0,
    layer = "body",
    tx = 12,
    ty = -4,
})
```

Optional defaults are `a=1`, `b=0`, `c=0`, `d=1`, `tx=0`, and `ty=0`.

`update_many` requires a dense array. Every entry must reference a unique Element from this exact
collection and contain at least one writable field. It validates the whole array before creating one
Document mutation, so an invalid entry never leaves a partial batch behind. An entry may use either a
complete `transform = { a, b, c, d, tx, ty }` matrix or any subset of `a`, `b`, `c`, `d`, `tx`, and
`ty`; subset fields preserve the Element's other transform components.

```lua
anim_frame.elements:update_many({
    { element = anim_frame.elements[1], tx = 10, ty = 20 },
    {
        element = anim_frame.elements[2],
        symbol = "hand",
        frame_num = 3,
        transform = { a = 1, b = 0, c = 0, d = 1, tx = 4, ty = 8 },
    },
})
anim_frame.elements:transform_all({ type = "translate", x = 2, y = 0 })
```

### Element

Writable fields: `symbol`, `frame`, `layer`, `a`, `b`, `c`, `d`, `tx`, and `ty`.

| API | Returns | Description |
| --- | --- | --- |
| `element:set_reference(symbol, frame)` | boolean | Set the Symbol name and Symbol Frame `num` reference |
| `element:set_layer(layer)` | boolean | Change the Layer |
| `element:set_transform(a, b, c, d, tx, ty)` | boolean | Set the affine transform directly |
| `element.draw_index` | integer | Current 1-based visual draw position; smaller indexes are in front |
| `element:place_above(other)` | boolean | Put this Element directly in front of `other` |
| `element:place_below(other)` | boolean | Put this Element directly behind `other` |
| `element:bring_to_front()` | boolean | Move this Element to the front |
| `element:send_to_back()` | boolean | Move this Element to the back |
| `element:clone()` | Element | Copy the Element and return the copy |
| `element:move_to(index)` | boolean | Move within the current Anim Frame's draw order |
| `element:move_to_parent(anim_frame)` | boolean | Move to the end of another Anim Frame |
| `element:transform(transform)` | boolean | Apply an additional transform |
| `element:remove()` | boolean | Remove the Element |

Important: `element.frame` is a Symbol Frame `num`, not an index into `symbol.frames`.
`element.frame_num` is an explicit alias for the same value. `frame:find_elements({ layer, symbol,
frame_num })` performs case-insensitive exact matching without trimming names; `matches_layer` and
`matches_symbol` follow the same rule.

The Element collection is the sole draw-order fact. The renderer draws smaller collection indexes in
front, so `draw_index == 1` is the front-most Element. Relative placement requires both Elements to
belong to the same Anim Frame. The helpers return `false` when the requested position is already true.

## Animation Crop and Comparison

`animation:crop(points)` accepts a dense array of 1 to 3 strictly increasing integer boundaries. A point
is the zero-based first frame of the following segment, so valid points for a frame count of `N` are
`1..N-1`; invalid, duplicate, unordered, or out-of-range points are rejected. The Document layer owns
all crop details: every segment has at least one frame, the first segment is `[0, point)`, the final
segment includes the last frame, facing suffixes are preserved, and existing same-name targets follow the
normal replacement rule.

```lua
local segments = animation:crop({ 34, 112 })
local pre, loop, pst = segments[1], segments[2], segments[3]
print(pre.id, loop.name, #pst.frames)
```

`utils.compare_anim_frames(left, right, options?)` and
`animation:compare_transition(other, options?)` compare Document values, not rendered pixels. A report
contains `equal`, Element/Event counts, `max_float_error`, and structured `mismatches`. Element IDs are
ignored. Symbol and Layer references are case-insensitive without trimming. Options are strict:

```lua
local report = utils.compare_anim_frames(left_frame, right_frame, {
    tolerance = 0.00001,
    compare_bounds = true,
    compare_events = true,
    compare_references = true,
    compare_draw_order = true,
})

local transition = animation:compare_transition(other_animation, {
    from_frame_index = #animation.frames - 1,
    to_frame_index = 0,
})
```

Transition indexes are zero-based. When `compare_draw_order = false`, equal Elements are matched as a
multiset instead of by their collection positions; ambiguous duplicate Elements are matched
deterministically but have no special identity beyond their values.

## Affine Utilities

`utils.affine` uses strict `{ a, b, c, d, tx, ty }` tables. It provides `multiply`, `compose`,
`inverse`, `apply_point`, `rotate_about`, `decompose`, and `from_element`. Unknown fields, non-finite
numbers, and singular inverses are rejected. An Element already stores its final render transform, so
there is no separate parent/world transform.

## Common Transforms

`transform` on Bank, Animation, AnimFrame, and Element accepts one of these tables:

```lua
{ type = "translate", x = 10, y = -5 }
{ type = "rotate", degrees = 15 }
{ type = "scale", x = 1.2, y = 0.8 }
{ type = "affine", a = 1, b = 0, c = 0, d = 1, tx = 10, ty = -5 }
```

All numeric values should be finite. Do not pass `NaN` or infinity.

Transforms are premultiplied onto each Element in world space. Both `scale` components must have an
absolute value of at least `0.001`, and the linear part of an `affine` transform must be invertible. On a
Bank, Animation, or AnimFrame, `translate` also moves the Anim Frame collision center, while `scale`
updates its collision center and size. `rotate` and `affine` modify Elements without automatically
recalculating collision bounds. Call `doc:recalculate_collision(...)` afterward when the collision bounds
must fit the transformed image content.

## Anti-Follow Symbol

```lua
animation:anti_follow({
    symbol = "body",
    frame_pattern = [[^0$]],
    maintain_scale = false,
})
```

This operation finds anchor Elements by Symbol name and an optional Frame pattern, then converts the other Elements into the anchor's local coordinate system. Calling it on a Bank processes every Animation in that Bank.

| Option | Required | Default | Description |
| --- | --- | --- | --- |
| `symbol` | Yes | None | Symbol name to match |
| `frame_pattern` | No | All Frames | Regular expression matched against the Element Frame number |
| `maintain_scale` | No | `false` | Preserve scale information |

## Follow Symbol

```lua
local target = assert(doc.banks:find("main").animations:find("idle"))
local child = assert(doc.banks:find("effects").animations:find("glow"))

target:follow_symbol(child, {
    symbol = "body",
    local_x = 0,
    local_y = 8,
    z_index_offset = 1,
})
```

This operation copies `child` content and attaches it to matching Elements in `target`. The `child` Animation is not modified.

| Option | Required | Default | Description |
| --- | --- | --- | --- |
| `symbol` | Yes | None | Anchor Symbol name |
| `frame_pattern` | No | All Frames | Regular expression matched against anchor Element Frame numbers |
| `all_matches` | No | `false` | Use every matching anchor instead of only the first |
| `local_x` / `local_y` | No | `0` | Local offset of the child Animation |
| `local_scale_x` / `local_scale_y` | No | `1` | Local scale of the child Animation |
| `local_rotation_degrees` | No | `0` | Local rotation of the child Animation |
| `inherit_position_x` / `inherit_position_y` | No | `true` | Inherit anchor position |
| `inherit_scale` | No | `true` | Inherit anchor scale |
| `inherit_rotation` | No | `true` | Inherit anchor rotation |
| `average_rotation` | No | `false` | Use averaged rotation |
| `z_index_offset` | No | `0` | Draw-order offset relative to the anchor |
| `alignment` | No | `"unaligned"` | Frame-length alignment mode |

Accepted `alignment` values:

- `"unaligned"`: preserve both original lengths.
- `"relength_child"`: fit the child Animation to the target length.
- `"relength_target"`: fit the target Animation to the child length.

## Search and Replace Elements

`scope` is a non-empty array of Bank, Animation, AnimFrame, or Element objects. Do not include duplicate or overlapping scopes.

### Exact Reference Replacement

```lua
doc:search_replace_elements({ animation }, {
    type = "reference",
    field = "symbol",
    search = "old_body",
    replacement = "new_body",
})
```

`field` accepts `"symbol"` or `"layer"`. Matching is case-insensitive. Omit `replacement` or set it to `nil` to remove matching Elements.

### Regular Expression Replacement

```lua
doc:search_replace_elements({ animation }, {
    type = "regex",
    query = {
        symbol = [[^(.*)_old$]],
        frame = [[^(\d+)$]],
        layer = [[^(.*)$]],
    },
    action = "replace",
    replacement = {
        symbol = "$s1_new",
        frame = "$n1",
        layer = "$l1",
    },
})
```

All three query fields are required, and an Element must match all three. These are regular expressions, not Lua patterns.

Accepted `action` values:

- `"replace"`: replace matches; `replacement` is required.
- `"remove"`: remove matches.
- `"keep"`: keep matches and remove non-matches.

Replacement text supports `$sN`, `$nN`, and `$lN` for Symbol, Frame, and Layer capture groups. Group `0` is the complete match. The resulting Frame must be a non-negative integer.

## Recalculate Collision Bounds

```lua
doc:recalculate_collision({ animation }, {
    builds = { build },
    hide_layers = { "shadow" },
    override_symbols = {
        swap_body = "body",
    },
    include_hidden = false,
})
```

`scope` is a non-empty array of Bank, Animation, or AnimFrame objects. Element is not accepted.

| Option | Required | Default | Description |
| --- | --- | --- | --- |
| `builds` | Yes | None | Non-empty Build array used to resolve Symbol Frames |
| `hide_layers` | No | Empty | Layer names ignored during calculation |
| `override_symbols` | No | Empty | Map from original Symbol names to replacement Symbol names |
| `include_hidden` | No | `false` | Include hidden content |

## Common Mistakes

### Calling a method with a dot

Use a colon so Lua passes the current object:

```lua
build:set_name("new_name")
```

### Assigning read-only fields or collections

`build.version = ...`, `build.symbols = ...`, and `doc.builds[1] = ...` are not allowed. Assign ordinary writable fields directly, and use the corresponding method for structural changes.

### Confusing Frame numbers with collection indexes

`symbol.frames[1]` is the first collection item. `symbol.frames:find(1)` searches for a Symbol Frame whose `num` is `1`.

### Using an object after removal

```lua
local build = doc.builds[1]
build:remove()
-- Do not access build after this point.
```

### Mutating order while iterating forward

When removing, moving, or changing an order-defining field, iterate backward or save the target objects before editing.

### Assuming a new parent is empty

New Builds, Symbols, Banks, Animations, and Anim Frames contain a minimal default subtree. Inspect existing children before deciding whether to reuse them or add more.

### Passing a relative resource or output path

`doc:import_resources`, `replace_image`, all image export APIs, and DMT workspace file commands use
controlled absolute paths only. A PNG file output must end in `.png`, and a PNG sequence destination
directory must not already exist. Scripts cannot use general filesystem APIs. Prefer `[[...]]` for Windows
paths.

## Available Environment and Default Limits

Lua basic functions and the `table`, `string`, `math`, and `utf8` libraries are available. `io`, `os`,
`package`, and `debug` are unavailable. Scripts cannot freely access files or start external processes.
Controlled file access is available only through `doc:import_resources`, `replace_image`, image export APIs,
and the DMT workspace file commands on `tool`.

Default safety limits:

| Resource | Limit |
| --- | --- |
| Source size | 1 MiB |
| Lua memory | 64 MiB |
| Instructions | 10,000,000 |
| Execution time | 5 seconds |
| Mutation operations | 10,000 |
| Output lines | 1,000 |
| Output line size | 4 KiB |
| Decoded images per run | 4 GiB |

Exceeding a limit stops the script, and none of that run's document changes are applied.

## External IPC Invocation

DST Mod Tool provides a local command-line entry point that sends a Lua request to the current app
instance. It is intended for automation scripts, editor integrations, and local AI Agents. It is not a
TCP, HTTP, or remote-control API.

### Command-Line Entry Point

Select exactly one source:

```bash
dst-app script --file /absolute/path/task.lua
dst-app script --text 'print(tool.document_revision)'
printf 'print(#doc.builds)' | dst-app script --stdin
dst-app script --help --lang en
```

- `--file`: run a UTF-8 Lua file; the path must be absolute.
- `--text`: run Lua source supplied as a command-line argument.
- `--stdin`: read the complete Lua source from standard input; useful for longer scripts and avoiding
  shell quoting issues.
- Using no source, more than one source, or an unknown option is an error.
- `script --help` prints this embedded guide without starting or connecting to the app. `--lang`
  accepts `en` or `zh-CN`; when omitted, the system locale is used when available.

### DMT Workspace Files

```lua
print(tool.document_path) -- absolute path or nil
tool:save_document() -- requires an existing binding
tool:save_document_as("/abs/new-workspace.dmt")
tool:open_document("/abs/other-workspace.dmt") -- terminal command
```

These commands never open a native file picker. `save_document_as` adds `.dmt` only when the supplied
absolute path has no extension; another explicit extension is rejected. `open_document` replaces the workspace, clears its history, waits
for Renderer resources, and terminates the current Lua run; it cannot be mixed with edits, undo/redo,
another tool command, or output after the call.

The executable inside a macOS app bundle is:

```bash
"/Applications/DST Mod Tool.app/Contents/MacOS/dst-app" \
    script --file /tmp/task.lua
```

The Windows release executable is named `DST Mod Tool.exe`:

```powershell
& "C:\Program Files\DST Mod Tool\DST Mod Tool.exe" `
    script --file "C:\Temp\task.lua"

Get-Content -Raw "C:\Temp\task.lua" |
    & "C:\Program Files\DST Mod Tool\DST Mod Tool.exe" script --stdin
```

When the app is already running, the script executes against that instance's current Animation Tool
workspace. The in-app page switches to Animation Tool and shows `Remote` in the title bar while the
request runs, but the app does not activate or take OS foreground focus. If no instance is running, the
command starts the normal visible application; its workspace is normally empty, so resources may be
loaded with `doc:import_resources`. A `.dmt` file cannot be opened through
`doc:import_resources`; use a dedicated `tool:open_document("/absolute/path/workspace.dmt")`
request instead. Because opening is terminal, do not mix it with edits, saves, exports, or other Tool
commands.

The command always writes one JSON value to stdout; no output-format option is required. The exit code is
`0` when the script report succeeds and `1` for a protocol error or failed script report. stderr is
reserved for argument and startup errors that cannot produce a normal IPC response.

### Reading the Response

A connected script request returns this envelope:

```json
{
  "version": 1,
  "request_id": 42,
  "response": {
    "type": "script",
    "report": {
      "ok": true,
      "origin": "external_ipc",
      "output": ["revision\t7"],
      "error": null,
      "document": {
        "changed": false,
        "before_revision": 7,
        "after_revision": 7,
        "history_label": null
      },
      "tool_results": [],
      "stats": {
        "elapsed_micros": 120,
        "instructions": 8,
        "mutation_stages": 0,
        "lua_memory_bytes": 24576,
        "loaded_image_bytes": 0
      }
    }
  }
}
```

At minimum, a caller must inspect:

1. Whether `response.type` is `"script"`; `"error"` is an IPC envelope error.
2. Whether `report.ok` is `true`; failure details are in `report.error`.
3. The lines produced by `print(...)` in `report.output`.
4. Whether the Document changed and its before/after revisions in `report.document`.
5. The `ok` value of every `report.tool_results` entry, which records deferred commands in execution
   order.

Each `tool_results` entry has a 1-based `index`, `command`, `ok`, and optional `message`. `undo` and
`redo` results also contain `requested_steps` and `applied_steps`, exposing the actual count after silent
clamping. Use stable enum fields for decisions instead of parsing natural-language `message` text.

On success, `report.error` is `null`. On failure, it contains `stage`, `code`, `message`, and an optional
`traceback`. `stats` is diagnostic data. It may be `null` when a request fails before the Lua runner starts
and must not be used as a business-success condition.

In particular, `report.ok == false` does not always mean that the Document is unchanged. If Lua and the
Document commit succeeded but a later `tool` command failed, the committed Document and earlier completed
commands remain in effect; commands after the failure are not executed.

### Protocol v1

Implement a direct IPC client only when the command-line entry point cannot be used. Both requests and
responses use:

1. A 4-byte little-endian unsigned payload length.
2. A UTF-8 JSON payload of that exact length.

Requests are limited to 2 MiB and responses to 8 MiB. The local endpoint is restricted to the current OS
user; the command-line entry point handles platform-specific endpoint discovery and connection details.

Text request example:

```json
{
  "version": 1,
  "request_id": 42,
  "command": {
    "type": "run_lua",
    "source": {
      "type": "text",
      "value": "print(tool.document_revision)"
    }
  }
}
```

Use this source object for a file:

```json
{
  "type": "file",
  "path": "/absolute/path/task.lua"
}
```

The request envelope, `command`, and `source` all reject unknown fields. `version` must currently be `1`.
The caller generates `request_id`; it is echoed in the response and must be checked against the request.

Stable IPC envelope error codes are:

| Code | Meaning |
| --- | --- |
| `invalid_request` | Invalid framing, JSON, or request size |
| `unsupported_version` | Unsupported protocol version |
| `timeout` | The app did not complete the request before the server deadline |
| `internal` | The endpoint, request channel, or service is unavailable |

The script report uses `request`, `read_source`, `lua`, `commit`, `tool_command`, or `cancelled` as
`error.stage`. Stable `error.code` values are:

| Code | Meaning |
| --- | --- |
| `busy` | Another script or mutually exclusive workspace task is running |
| `invalid_source` / `read_source` | Invalid source arguments or a script file read failure |
| `lua_syntax` / `lua_runtime` | Lua syntax or runtime error |
| `document_edit` | Document edit validation failure |
| `resource` | Image or animation resource loading failure |
| `limit_exceeded` | Source, time, instruction, memory, output, or image budget exceeded |
| `commit_failed` | The staged Document transaction could not be committed |
| `tool_command_failed` | Selection, playback, History, preview rule, or image export command failed |
| `cancelled` | The request was cancelled |
| `internal` | Internal script execution service error |

The server waits up to 60 seconds for completion, while the command-line client waits up to 65 seconds for
a response. A timeout sends a cooperative cancellation signal that prevents work not yet started; it does
not undo completed Document commits or `tool` commands. Only one script runs at a time, and scripts are
mutually exclusive with workspace open, save, and reset tasks. Wait and retry after `busy` instead of
replaying requests concurrently.

## Guide for AI Agents

This chapter is for an AI Agent that can create Lua files, run local commands, and view local images. The
goal is to perform reviewable animation inspection, editing, app control, and visual validation through the
restricted scripting API, not to edit `.dmt` or binary assets directly.

### Recommended Workflow

1. **Read first.** Use a read-only script to establish the revision, Builds, Banks, Animations, and current
   selection.
2. **Resolve exact targets.** Use `find` and `assert`; never guess names, collection indexes, or Frame
   `num` values.
3. **Make focused edits.** Set a meaningful History name with `doc:set_label`, and keep each request to one
   related group of changes.
4. **Separate History commands.** Send `tool:undo()` or `tool:redo()` in its own request, never alongside
   Document edits.
5. **Inspect the report.** Check `report.ok`, `report.error`, `report.document`, and every
   `report.tool_results` entry.
6. **Check the final state when needed.** For IPC, inspect `report.final_tool_state` only when the script
   queued selection/playback, preview, History, `open_document`, or `save_document_as`; when present it is
   the authoritative App state after deferred commands complete. The field is omitted for read-only runs,
   Document-only edits, ordinary saves, and exports. Send a second read-only request only when you need to
   inspect a later asynchronous Renderer result.
7. **Validate visually.** Export one size-limited PNG first and inspect it with the Agent's own image-viewing
   capability. A successful status only proves completion, not that the visual result matches the request.

Print concise, labeled summaries instead of dumping the entire Document. Output has line and line-length
limits, and unrelated data makes decisions less reliable:

```lua
print("revision", tool.document_revision)
print("builds", #doc.builds)
print("banks", #doc.banks)

for _, bank in ipairs(doc.banks) do
    print("bank", bank.name, "animations", #bank.animations)
end

local selected = tool.selection.animation
if selected then
    print("selected_animation", selected.name, #selected.frames)
end
```

### Editing an Animation

Assert that both the parent and target exist before changing a field:

```lua
doc:set_label("Rename idle animation")

local bank = assert(doc.banks:find("wilson"), "Bank not found")
local animation = assert(bank.animations:find("idle"), "Animation not found")
animation.name = "idle_loop"
```

Do not directly edit `.dmt`, `build.bin`, `anim.bin`, or application preference files from the external
process. Use `tool:open_document` in a dedicated request to open an existing `.dmt`; it replaces the
workspace and terminates that Lua run. Use `doc:import_resources` for ZIP, SCML, PSD, Spine JSON, PNG,
and other supported resources. When a name is uncertain, print candidates and make the edit in a later
request after resolving the user's intended target.

### Controlling the App

Selection, playback, and preview rules are `tool` commands that run in order after the Document commit:

```lua
local bank = assert(doc.banks:find("wilson"), "Bank not found")
local animation = assert(bank.animations:find("idle_loop"), "Animation not found")

tool:select_animation(animation)
tool:select_frame(animation.frames[1])
tool:set_hide_layer("arm_normal", true)
tool:set_override_symbol("swap_object", "swap_spear")
tool:play()
```

Use `tool:select_frame(frame)` to select and seek to any Anim Frame; it pauses playback automatically.
Use `tool:pause()` to pause. Use `tool:set_override_symbol("swap_object", nil)` to clear one override and
`tool:set_hide_layer("arm_normal", false)` to show a hidden Layer. A failed command stops later commands,
so do not assume an export or control after a failed playback command ran. Send a new read-only request to
confirm the final selection, playback, or preview rules.

### Rendering Images for AI Inspection

Render the first frame of the selected Animation:

```lua
local animation = assert(tool.selection.animation, "Select an Animation first")
local frame = assert(animation.frames[1], "Animation has no frames")

frame:export_png([[/absolute/tmp/dst-preview.png]], {
    max_dimension = 1024,
})
```

Render a Symbol Frame:

```lua
local build = assert(doc.builds:find("wilson"), "Build not found")
local symbol = assert(build.symbols:find("body"), "Symbol not found")
local frame = assert(symbol.frames:find(0), "Symbol Frame not found")

frame:export_png([[/absolute/tmp/body-frame.png]])
```

Export a full sequence only when temporal behavior must be inspected:

```lua
local animation = assert(tool.selection.animation, "Select an Animation first")
animation:export_png_sequence([[/absolute/tmp/idle-sequence-001]], {
    max_dimension = 1024,
})
```

A single-frame export may atomically replace the same path. Every sequence export needs a fresh directory
that does not already exist. IPC responses do not contain image bytes. After confirming the corresponding
`tool_results` entry succeeded, open the generated PNG with the Agent's own file and vision tools. Checking
one frame is usually faster; export a sequence only when motion continuity matters. Never claim visual
success from the exit code alone.

### Agent Checklist

- Use absolute paths, and prefer Lua `[[...]]` strings for Windows paths.
- Resolve targets before each edit and verify them with a second read request afterward.
- Give user-visible Document edits a clear History label.
- Within one script, use the projected `tool` values to reason about queued commands; after deferred App
  execution, use `report.final_tool_state` when it is present as the authoritative final state.
- Do not treat an unchanged Document revision as evidence that a `tool` command succeeded.
- Never ignore `tool_results`, especially with multiple control or export commands.
- Never mix undo/redo with Document edits in one request.
- Never reuse an existing PNG sequence output directory.
- Do not infer image contents from IPC output; open and inspect the rendered result.

stderr (0 chars):
returncode: 0
---
