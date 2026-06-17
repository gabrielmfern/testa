const std = @import("std");
const c = @import("node_c");
const esb = @import("esbuild_c");

var passed_tests: u32 = 0;
var failed_tests: u32 = 0;
var io: std.Io = undefined;

// Phase timing, gated on TESTA_TIMING. lap() records the time since the last
// lap; results are dumped together at the end so they don't interleave with
// the buffered per-test output.
var timing_on: bool = false;
var timing_last: std.Io.Timestamp = undefined;
var timings: [16]struct { label: []const u8, d: std.Io.Duration } = undefined;
var timings_n: usize = 0;
fn performance_timing_lap(label: []const u8) void {
    if (!timing_on or timings_n >= timings.len) return;
    timings[timings_n] = .{ .label = label, .d = timing_last.untilNow(io, .awake) };
    timings_n += 1;
    timing_last = std.Io.Timestamp.now(io, .awake);
}

// ===== expect(): vitest-compatible matchers, all native =====
//
// Each matcher is one shared C callback. expect(x) returns an object whose
// prototype carries every matcher; the matcher reads `actual` back off the
// receiver (this._a) and decodes which matcher + whether .not from the integer
// in its function Data slot. The two prototypes (positive / negated) are built
// once and cached, so a hot expect() call only allocates two small objects.

const Matcher = enum(i32) {
    toBe,
    toEqual,
    toStrictEqual,
    toBeDefined,
    toBeUndefined,
    toBeNull,
    toBeNaN,
    toBeTruthy,
    toBeFalsy,
    toBeGreaterThan,
    toBeGreaterThanOrEqual,
    toBeLessThan,
    toBeLessThanOrEqual,
    toBeCloseTo,
    toContain,
    toContainEqual,
    toHaveLength,
    toHaveProperty,
    toMatch,
    toMatchObject,
    toBeInstanceOf,
    toBeTypeOf,
    toThrow,
};

const Entry = struct { name: [*:0]const u8, id: Matcher };
const matcher_table = [_]Entry{
    .{ .name = "toBe", .id = .toBe },
    .{ .name = "toEqual", .id = .toEqual },
    .{ .name = "toStrictEqual", .id = .toStrictEqual },
    .{ .name = "toBeDefined", .id = .toBeDefined },
    .{ .name = "toBeUndefined", .id = .toBeUndefined },
    .{ .name = "toBeNull", .id = .toBeNull },
    .{ .name = "toBeNaN", .id = .toBeNaN },
    .{ .name = "toBeTruthy", .id = .toBeTruthy },
    .{ .name = "toBeFalsy", .id = .toBeFalsy },
    .{ .name = "toBeGreaterThan", .id = .toBeGreaterThan },
    .{ .name = "toBeGreaterThanOrEqual", .id = .toBeGreaterThanOrEqual },
    .{ .name = "toBeLessThan", .id = .toBeLessThan },
    .{ .name = "toBeLessThanOrEqual", .id = .toBeLessThanOrEqual },
    .{ .name = "toBeCloseTo", .id = .toBeCloseTo },
    .{ .name = "toContain", .id = .toContain },
    .{ .name = "toContainEqual", .id = .toContainEqual },
    .{ .name = "toHaveLength", .id = .toHaveLength },
    .{ .name = "toHaveProperty", .id = .toHaveProperty },
    .{ .name = "toMatch", .id = .toMatch },
    .{ .name = "toMatchObject", .id = .toMatchObject },
    .{ .name = "toBeInstanceOf", .id = .toBeInstanceOf },
    .{ .name = "toBeTypeOf", .id = .toBeTypeOf },
    .{ .name = "toThrow", .id = .toThrow },
    .{ .name = "toThrowError", .id = .toThrow },
};

const NOT_BIT: i32 = 1 << 16;
// Persistent so the prototypes outlive the expect() callback that built them.
var proto_pos: ?*c.v8_global = null;
var proto_neg: ?*c.v8_global = null;

fn regexpEq(ctx: ?*c.v8_local_context, isolate: ?*c.v8_isolate, a: ?*c.v8_local_value, b: ?*c.v8_local_value) bool {
    const sa = c.v8_object_get_key(ctx, a, "source");
    defer c.v8_local_value_free(sa);
    const sb = c.v8_object_get_key(ctx, b, "source");
    defer c.v8_local_value_free(sb);
    const fa = c.v8_object_get_key(ctx, a, "flags");
    defer c.v8_local_value_free(fa);
    const fb = c.v8_object_get_key(ctx, b, "flags");
    defer c.v8_local_value_free(fb);
    return c.v8_string_equals(isolate, sa, sb) and c.v8_string_equals(isolate, fa, fb);
}

// ponytail: strict mode covers undefined-key differences but not prototype
// identity or sparse arrays. Add those if a test needs the distinction.
fn deepEqual(ctx: ?*c.v8_local_context, isolate: ?*c.v8_isolate, a: ?*c.v8_local_value, b: ?*c.v8_local_value, strict: bool) bool {
    if (c.v8_value_same_value(a, b)) return true;
    if (!c.v8_value_is_object(a) or !c.v8_value_is_object(b)) return false;
    if (c.v8_value_is_function(a) or c.v8_value_is_function(b)) return false;

    const ad = c.v8_value_is_date(a);
    if (ad != c.v8_value_is_date(b)) return false;
    if (ad) return c.v8_value_number(ctx, a) == c.v8_value_number(ctx, b);

    const ar = c.v8_value_is_regexp(a);
    if (ar != c.v8_value_is_regexp(b)) return false;
    if (ar) return regexpEq(ctx, isolate, a, b);

    const aarr = c.v8_value_is_array(a);
    if (aarr != c.v8_value_is_array(b)) return false;
    if (aarr) {
        const la = c.v8_array_length(a);
        if (la != c.v8_array_length(b)) return false;
        var i: u32 = 0;
        while (i < la) : (i += 1) {
            const ea = c.v8_array_get(ctx, a, i);
            defer c.v8_local_value_free(ea);
            const eb = c.v8_array_get(ctx, b, i);
            defer c.v8_local_value_free(eb);
            if (!deepEqual(ctx, isolate, ea, eb, strict)) return false;
        }
        return true;
    }

    const amap = c.v8_value_is_map(a);
    if (amap != c.v8_value_is_map(b)) return false;
    if (amap) {
        const aa = c.v8_map_as_array(a);
        defer c.v8_local_value_free(aa);
        const ba = c.v8_map_as_array(b);
        defer c.v8_local_value_free(ba);
        return mapArrEq(ctx, isolate, aa, ba, strict);
    }

    const aset = c.v8_value_is_set(a);
    if (aset != c.v8_value_is_set(b)) return false;
    if (aset) {
        const aa = c.v8_set_as_array(a);
        defer c.v8_local_value_free(aa);
        const ba = c.v8_set_as_array(b);
        defer c.v8_local_value_free(ba);
        if (c.v8_array_length(aa) != c.v8_array_length(ba)) return false;
        return arrContains_all(ctx, isolate, aa, ba, strict);
    }

    return objEq(ctx, isolate, a, b, strict);
}

// Every element of `needles` is deep-equal to some element of `hay`.
fn arrContains_all(ctx: ?*c.v8_local_context, isolate: ?*c.v8_isolate, hay: ?*c.v8_local_value, needles: ?*c.v8_local_value, strict: bool) bool {
    const ln = c.v8_array_length(needles);
    var i: u32 = 0;
    while (i < ln) : (i += 1) {
        const e = c.v8_array_get(ctx, needles, i);
        defer c.v8_local_value_free(e);
        if (!arrHas(ctx, isolate, hay, e, true, strict)) return false;
    }
    return true;
}

fn arrHas(ctx: ?*c.v8_local_context, isolate: ?*c.v8_isolate, hay: ?*c.v8_local_value, needle: ?*c.v8_local_value, deep: bool, strict: bool) bool {
    const l = c.v8_array_length(hay);
    var i: u32 = 0;
    while (i < l) : (i += 1) {
        const e = c.v8_array_get(ctx, hay, i);
        defer c.v8_local_value_free(e);
        if (deep) {
            if (deepEqual(ctx, isolate, e, needle, strict)) return true;
        } else if (c.v8_value_strict_equals(e, needle)) return true;
    }
    return false;
}

fn mapArrEq(ctx: ?*c.v8_local_context, isolate: ?*c.v8_isolate, aa: ?*c.v8_local_value, ba: ?*c.v8_local_value, strict: bool) bool {
    const la = c.v8_array_length(aa);
    if (la != c.v8_array_length(ba)) return false;
    var i: u32 = 0;
    while (i < la) : (i += 2) {
        const ka = c.v8_array_get(ctx, aa, i);
        defer c.v8_local_value_free(ka);
        const va = c.v8_array_get(ctx, aa, i + 1);
        defer c.v8_local_value_free(va);
        var found = false;
        var j: u32 = 0;
        while (j < la) : (j += 2) {
            const kb = c.v8_array_get(ctx, ba, j);
            defer c.v8_local_value_free(kb);
            if (deepEqual(ctx, isolate, ka, kb, strict)) {
                const vb = c.v8_array_get(ctx, ba, j + 1);
                defer c.v8_local_value_free(vb);
                if (deepEqual(ctx, isolate, va, vb, strict)) {
                    found = true;
                    break;
                }
            }
        }
        if (!found) return false;
    }
    return true;
}

fn effKeyCount(ctx: ?*c.v8_local_context, isolate: ?*c.v8_isolate, obj: ?*c.v8_local_value, keys: ?*c.v8_local_value, strict: bool) u32 {
    if (strict) return c.v8_array_length(keys);
    var n: u32 = 0;
    const l = c.v8_array_length(keys);
    var i: u32 = 0;
    while (i < l) : (i += 1) {
        const kv = c.v8_array_get(ctx, keys, i);
        defer c.v8_local_value_free(kv);
        const ks = c.v8_value_to_utf8(isolate, kv);
        defer c.v8_utf8_free(ks);
        const v = c.v8_object_get_key(ctx, obj, ks);
        defer c.v8_local_value_free(v);
        if (!c.v8_value_is_undefined(v)) n += 1;
    }
    return n;
}

fn objEq(ctx: ?*c.v8_local_context, isolate: ?*c.v8_isolate, a: ?*c.v8_local_value, b: ?*c.v8_local_value, strict: bool) bool {
    const ka = c.v8_object_own_keys(ctx, a);
    defer c.v8_local_value_free(ka);
    const kb = c.v8_object_own_keys(ctx, b);
    defer c.v8_local_value_free(kb);
    if (effKeyCount(ctx, isolate, a, ka, strict) != effKeyCount(ctx, isolate, b, kb, strict)) return false;

    const la = c.v8_array_length(ka);
    var i: u32 = 0;
    while (i < la) : (i += 1) {
        const kv = c.v8_array_get(ctx, ka, i);
        defer c.v8_local_value_free(kv);
        const ks = c.v8_value_to_utf8(isolate, kv);
        defer c.v8_utf8_free(ks);
        const av = c.v8_object_get_key(ctx, a, ks);
        defer c.v8_local_value_free(av);
        if (!strict and c.v8_value_is_undefined(av)) continue;
        if (!c.v8_object_has_key(ctx, b, ks)) return false;
        const bv = c.v8_object_get_key(ctx, b, ks);
        defer c.v8_local_value_free(bv);
        if (!deepEqual(ctx, isolate, av, bv, strict)) return false;
    }
    return true;
}

fn matchObject(ctx: ?*c.v8_local_context, isolate: ?*c.v8_isolate, actual: ?*c.v8_local_value, expected: ?*c.v8_local_value) bool {
    if (!c.v8_value_is_object(expected)) return deepEqual(ctx, isolate, actual, expected, false);
    if (!c.v8_value_is_object(actual)) return false;
    const keys = c.v8_object_own_keys(ctx, expected);
    defer c.v8_local_value_free(keys);
    const l = c.v8_array_length(keys);
    var i: u32 = 0;
    while (i < l) : (i += 1) {
        const kv = c.v8_array_get(ctx, keys, i);
        defer c.v8_local_value_free(kv);
        const ks = c.v8_value_to_utf8(isolate, kv);
        defer c.v8_utf8_free(ks);
        if (!c.v8_object_has_key(ctx, actual, ks)) return false;
        const ev = c.v8_object_get_key(ctx, expected, ks);
        defer c.v8_local_value_free(ev);
        const av = c.v8_object_get_key(ctx, actual, ks);
        defer c.v8_local_value_free(av);
        const nested = c.v8_value_is_object(ev) and c.v8_value_is_object(av) and
            !c.v8_value_is_array(ev) and !c.v8_value_is_function(ev);
        const ok = if (nested) matchObject(ctx, isolate, av, ev) else deepEqual(ctx, isolate, av, ev, false);
        if (!ok) return false;
    }
    return true;
}

fn containsVal(ctx: ?*c.v8_local_context, isolate: ?*c.v8_isolate, hay: ?*c.v8_local_value, needle: ?*c.v8_local_value, deep: bool) bool {
    if (c.v8_value_is_string(hay)) return c.v8_string_contains(isolate, hay, needle);
    if (c.v8_value_is_array(hay)) return arrHas(ctx, isolate, hay, needle, deep, false);
    if (c.v8_value_is_set(hay)) {
        const a = c.v8_set_as_array(hay);
        defer c.v8_local_value_free(a);
        return arrHas(ctx, isolate, a, needle, deep, false);
    }
    return false;
}

fn lengthOf(ctx: ?*c.v8_local_context, actual: ?*c.v8_local_value) ?u64 {
    if (c.v8_value_is_string(actual)) {
        const n = c.v8_string_length(actual);
        return if (n < 0) null else @intCast(n);
    }
    if (c.v8_value_is_array(actual)) return c.v8_array_length(actual);
    if (c.v8_value_is_object(actual)) {
        const l = c.v8_object_get_key(ctx, actual, "length");
        defer c.v8_local_value_free(l);
        if (c.v8_value_is_number(l)) return @intFromFloat(c.v8_value_number(ctx, l));
    }
    return null;
}

fn matchStr(ctx: ?*c.v8_local_context, isolate: ?*c.v8_isolate, actual: ?*c.v8_local_value, pattern: ?*c.v8_local_value) bool {
    if (!c.v8_value_is_string(actual)) return false;
    if (c.v8_value_is_regexp(pattern)) {
        const testfn = c.v8_object_get_key(ctx, pattern, "test");
        defer c.v8_local_value_free(testfn);
        if (!c.v8_value_is_function(testfn)) return false;
        var argv = [_]?*c.v8_local_value{actual};
        const r = c.v8_function_call(ctx, testfn, pattern, 1, &argv);
        if (r == null) return false;
        defer c.v8_local_value_free(r);
        return c.v8_value_boolean(isolate, r);
    }
    return c.v8_string_contains(isolate, actual, pattern);
}

fn checkThrow(ctx: ?*c.v8_local_context, isolate: ?*c.v8_isolate, fnval: ?*c.v8_local_value, expected: ?*c.v8_local_value) bool {
    if (!c.v8_value_is_function(fnval)) return false;
    const recv = c.v8_undefined(isolate);
    defer c.v8_local_value_free(recv);
    const tc = c.v8_try_catch_new(isolate);
    defer c.v8_try_catch_free(tc);
    const r = c.v8_function_call(ctx, fnval, recv, 0, null);
    if (r != null) c.v8_local_value_free(r);
    if (!c.v8_try_catch_has_caught(tc)) return false;
    if (expected == null) return true;

    const exc = c.v8_try_catch_exception(tc);
    defer c.v8_local_value_free(exc);
    var msgbox: ?*c.v8_local_value = null;
    if (c.v8_value_is_object(exc)) msgbox = c.v8_object_get_key(ctx, exc, "message");
    defer if (msgbox != null) c.v8_local_value_free(msgbox);
    const target = if (msgbox != null) msgbox else exc;
    const exp = expected.?;

    if (c.v8_value_is_string(exp)) return c.v8_string_contains(isolate, target, exp);
    if (c.v8_value_is_regexp(exp)) return matchStr(ctx, isolate, target, exp);
    if (c.v8_value_is_function(exp)) return c.v8_value_instance_of(ctx, exc, exp);
    if (c.v8_value_is_object(exp)) {
        const em = c.v8_object_get_key(ctx, exp, "message");
        defer c.v8_local_value_free(em);
        return c.v8_string_equals(isolate, target, em);
    }
    return false;
}

const PathResult = struct { has: bool, value: ?*c.v8_local_value };

fn getPath(ctx: ?*c.v8_local_context, isolate: ?*c.v8_isolate, obj: ?*c.v8_local_value, path: ?*c.v8_local_value) PathResult {
    var cur: ?*c.v8_local_value = obj;
    var owned = false;
    const is_arr = c.v8_value_is_array(path);
    const count: u32 = if (is_arr) c.v8_array_length(path) else 0;
    var path_str: [*c]u8 = null;
    defer if (path_str != null) c.v8_utf8_free(path_str);
    if (!is_arr) path_str = c.v8_value_to_utf8(isolate, path);

    var it = if (is_arr) undefined else std.mem.splitScalar(u8, std.mem.span(path_str), '.');
    var i: u32 = 0;
    while (true) {
        var keybuf: [256]u8 = undefined;
        const key: [:0]const u8 = blk: {
            if (is_arr) {
                if (i >= count) break;
                const kv = c.v8_array_get(ctx, path, i);
                defer c.v8_local_value_free(kv);
                const ks = c.v8_value_to_utf8(isolate, kv);
                defer c.v8_utf8_free(ks);
                break :blk std.fmt.bufPrintZ(&keybuf, "{s}", .{std.mem.span(ks)}) catch break;
            } else {
                const part = it.next() orelse break;
                break :blk std.fmt.bufPrintZ(&keybuf, "{s}", .{part}) catch break;
            }
        };
        i += 1;
        if (cur == null or !c.v8_value_is_object(cur) or !c.v8_object_has_key(ctx, cur, key)) {
            if (owned) c.v8_local_value_free(cur);
            return .{ .has = false, .value = null };
        }
        const next = c.v8_object_get_key(ctx, cur, key);
        if (owned) c.v8_local_value_free(cur);
        cur = next;
        owned = true;
    }
    return .{ .has = owned, .value = if (owned) cur else null };
}

fn matcherCallback(info: ?*const c.v8_function_callback_info) callconv(.c) void {
    const isolate = c.v8_function_callback_info_isolate(info);
    const ctx = c.v8_isolate_get_current_context(isolate);
    defer c.v8_local_context_free(ctx);
    const data = c.v8_function_callback_info_data(info);
    defer c.v8_local_value_free(data);
    const raw: i32 = @intFromFloat(c.v8_value_number(ctx, data));
    const negated = (raw & NOT_BIT) != 0;
    const id: Matcher = @enumFromInt(raw & 0xFFFF);
    const this = c.v8_function_callback_info_this(info);
    defer c.v8_local_value_free(this);
    const actual = c.v8_object_get_key(ctx, this, "_a");
    defer c.v8_local_value_free(actual);
    const argc = c.v8_function_callback_info_length(info);

    const arg0: ?*c.v8_local_value = if (argc > 0) c.v8_function_callback_info_get(info, 0) else null;
    defer if (arg0 != null) c.v8_local_value_free(arg0);

    var pass = false;
    switch (id) {
        .toBe => pass = c.v8_value_same_value(actual, arg0),
        .toEqual => pass = deepEqual(ctx, isolate, actual, arg0, false),
        .toStrictEqual => pass = deepEqual(ctx, isolate, actual, arg0, true),
        .toBeDefined => pass = !c.v8_value_is_undefined(actual),
        .toBeUndefined => pass = c.v8_value_is_undefined(actual),
        .toBeNull => pass = c.v8_value_is_null(actual),
        .toBeNaN => pass = c.v8_value_is_number(actual) and std.math.isNan(c.v8_value_number(ctx, actual)),
        .toBeTruthy => pass = c.v8_value_boolean(isolate, actual),
        .toBeFalsy => pass = !c.v8_value_boolean(isolate, actual),
        .toBeGreaterThan => pass = c.v8_value_number(ctx, actual) > c.v8_value_number(ctx, arg0),
        .toBeGreaterThanOrEqual => pass = c.v8_value_number(ctx, actual) >= c.v8_value_number(ctx, arg0),
        .toBeLessThan => pass = c.v8_value_number(ctx, actual) < c.v8_value_number(ctx, arg0),
        .toBeLessThanOrEqual => pass = c.v8_value_number(ctx, actual) <= c.v8_value_number(ctx, arg0),
        .toBeCloseTo => {
            var precision: f64 = 2;
            if (argc > 1) {
                const p = c.v8_function_callback_info_get(info, 1);
                defer c.v8_local_value_free(p);
                precision = c.v8_value_number(ctx, p);
            }
            const diff = @abs(c.v8_value_number(ctx, actual) - c.v8_value_number(ctx, arg0));
            pass = diff < std.math.pow(f64, 10, -precision) / 2;
        },
        .toContain => pass = containsVal(ctx, isolate, actual, arg0, false),
        .toContainEqual => pass = containsVal(ctx, isolate, actual, arg0, true),
        .toHaveLength => {
            const len = lengthOf(ctx, actual);
            pass = len != null and @as(f64, @floatFromInt(len.?)) == c.v8_value_number(ctx, arg0);
        },
        .toHaveProperty => {
            const res = getPath(ctx, isolate, actual, arg0);
            defer if (res.value != null) c.v8_local_value_free(res.value);
            if (!res.has) {
                pass = false;
            } else if (argc > 1) {
                const want = c.v8_function_callback_info_get(info, 1);
                defer c.v8_local_value_free(want);
                pass = deepEqual(ctx, isolate, res.value, want, false);
            } else pass = true;
        },
        .toMatch => pass = matchStr(ctx, isolate, actual, arg0),
        .toMatchObject => pass = matchObject(ctx, isolate, actual, arg0),
        .toBeInstanceOf => pass = c.v8_value_instance_of(ctx, actual, arg0),
        .toBeTypeOf => {
            const t = c.v8_value_typeof(isolate, actual);
            defer c.v8_utf8_free(t);
            const es = c.v8_value_to_utf8(isolate, arg0);
            defer c.v8_utf8_free(es);
            pass = std.mem.eql(u8, std.mem.span(t), std.mem.span(es));
        },
        .toThrow => pass = checkThrow(ctx, isolate, actual, arg0),
    }

    const ok = if (negated) !pass else pass;
    if (ok) return;

    const a_s = c.v8_value_to_utf8(isolate, actual);
    defer c.v8_utf8_free(a_s);
    const not_s = if (negated) " not" else "";
    const name = @tagName(id);
    if (argc > 0) {
        const e_s = c.v8_value_to_utf8(isolate, arg0);
        defer c.v8_utf8_free(e_s);

        var buf: [512]u8 = undefined;
        const msg = std.fmt.bufPrintZ(
            &buf,
            "expected {s}{s} {s} {s}",
            .{ std.mem.span(a_s), not_s, name, std.mem.span(e_s) },
        ) catch "assertion failed";
        c.v8_isolate_throw_error(isolate, msg);
    } else {
        var buf: [512]u8 = undefined;
        const msg = std.fmt.bufPrintZ(
            &buf,
            "expected {s}{s} {s}",
            .{ std.mem.span(a_s), not_s, name },
        ) catch "assertion failed";
        c.v8_isolate_throw_error(isolate, msg);
    }
}

fn buildProto(ctx: ?*c.v8_local_context, isolate: ?*c.v8_isolate, negated: bool) ?*c.v8_local_value {
    const proto = c.v8_object_new(isolate);
    const not_flag: i32 = if (negated) NOT_BIT else 0;
    inline for (matcher_table) |m| {
        const data = c.v8_integer_new(isolate, @intFromEnum(m.id) | not_flag);
        const fnv = c.v8_function_new(ctx, &matcherCallback, data);
        c.v8_object_set(ctx, proto, m.name, fnv);
        c.v8_local_value_free(fnv);
        c.v8_local_value_free(data);
    }
    return proto;
}

fn expectCallback(info: ?*const c.v8_function_callback_info) callconv(.c) void {
    const isolate = c.v8_function_callback_info_isolate(info);
    const ctx = c.v8_isolate_get_current_context(isolate);
    defer c.v8_local_context_free(ctx);
    const actual = c.v8_function_callback_info_get(info, 0);
    defer c.v8_local_value_free(actual);

    if (proto_pos == null) {
        const p = buildProto(ctx, isolate, false);
        defer c.v8_local_value_free(p);
        proto_pos = c.v8_global_new(isolate, p);
        const n = buildProto(ctx, isolate, true);
        defer c.v8_local_value_free(n);
        proto_neg = c.v8_global_new(isolate, n);
    }
    const pp = c.v8_global_get(isolate, proto_pos);
    defer c.v8_local_value_free(pp);
    const pn = c.v8_global_get(isolate, proto_neg);
    defer c.v8_local_value_free(pn);

    const obj = c.v8_object_new(isolate);
    defer c.v8_local_value_free(obj);
    c.v8_object_set_prototype(ctx, obj, pp);
    c.v8_object_set(ctx, obj, "_a", actual);

    const not_obj = c.v8_object_new(isolate);
    defer c.v8_local_value_free(not_obj);
    c.v8_object_set_prototype(ctx, not_obj, pn);
    c.v8_object_set(ctx, not_obj, "_a", actual);
    c.v8_object_set(ctx, obj, "not", not_obj);

    c.v8_function_callback_info_set_return_value(info, obj);
}

// test(name, closure): run it now, await it if async, time it, report a line.
fn testCallback(parameters: ?*const c.v8_function_callback_info) callconv(.c) void {
    const isolate = c.v8_function_callback_info_isolate(parameters);
    const ctx = c.v8_isolate_get_current_context(isolate);
    defer c.v8_local_context_free(ctx);

    const name_val = c.v8_function_callback_info_get(parameters, 0);
    defer c.v8_local_value_free(name_val);
    const closure = c.v8_function_callback_info_get(parameters, 1);
    defer c.v8_local_value_free(closure);

    const name = c.v8_value_to_utf8(isolate, name_val);
    defer c.v8_utf8_free(name);

    const tc = c.v8_try_catch_new(isolate);
    defer c.v8_try_catch_free(tc);

    const start = std.Io.Timestamp.now(io, .awake);
    const closure_returned_value = c.v8_function_call(ctx, closure, null, 0, null);
    defer if (closure_returned_value != null) c.v8_local_value_free(closure_returned_value);

    var failed = c.v8_try_catch_has_caught(tc);
    var test_exception: ?*c.v8_local_value = null;
    if (failed) {
        test_exception = c.v8_try_catch_exception(tc);
    } else if (closure_returned_value != null and c.v8_value_is_promise(closure_returned_value)) {
        // We are the handler; mark before it can settle so a rejection never
        // counts as an unhandled rejection (which aborts the process).
        c.v8_promise_mark_as_handled(closure_returned_value);

        while (c.v8_promise_state(closure_returned_value) == c.V8_PROMISE_PENDING) {
            c.v8_isolate_perform_microtask_checkpoint(isolate);
            if (c.v8_promise_state(closure_returned_value) != c.V8_PROMISE_PENDING) break;
            _ = c.v8_event_loop_run_once(isolate);
        }

        if (c.v8_promise_state(closure_returned_value) == c.V8_PROMISE_REJECTED) {
            failed = true;
            test_exception = c.v8_promise_result(closure_returned_value);
        }
    }
    defer if (test_exception != null) c.v8_local_value_free(test_exception);
    const test_duration = start.untilNow(io, .awake);

    var buffer: [128]u8 = undefined;
    var stderr = std.Io.File.stderr().writer(io, &buffer);
    if (failed) {
        failed_tests += 1;
        const emsg = c.v8_value_to_utf8(isolate, test_exception);
        defer c.v8_utf8_free(emsg);
        stderr.interface.print(
            "not ok {s} ({f})\n  {s}\n",
            .{ std.mem.span(name), test_duration, std.mem.span(emsg) },
        ) catch {};
    } else {
        passed_tests += 1;
        stderr.interface.print(
            "ok {s} ({f})\n",
            .{ std.mem.span(name), test_duration },
        ) catch {};
    }
    stderr.interface.flush() catch {};
}

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    io = init.io;
    timing_on = init.environ_map.contains("TESTA_TIMING");
    timing_last = std.Io.Timestamp.now(io, .awake);

    const args = try init.minimal.args.toSlice(arena);

    const argv = try arena.alloc([*c]u8, args.len);
    argv[0] = @constCast(args[0].ptr);
    for (args[1..], 0..) |a, j| argv[1 + j] = @constCast(a.ptr);
    const argc: c_int = @intCast(argv.len);

    const flags = c.NODE_INIT_NO_INITIALIZE_V8 | c.NODE_INIT_NO_INITIALIZE_NODE_V8_PLATFORM;
    const result = c.node_initialize_once_per_process(argc, argv.ptr, flags) orelse
        return error.FailedToNodeInit;
    defer c.node_teardown_once_per_process();
    defer c.node_init_result_free(result);
    performance_timing_lap("node init");

    var i: c_int = 0;
    while (i < c.node_init_result_error_count(result)) : (i += 1) {
        std.debug.print("{s}: {s}\n", .{ args[0], c.node_init_result_error_at(result, i) });
    }
    if (c.node_init_result_early_return(result)) {
        std.process.exit(@intCast(c.node_init_result_exit_code(result)));
    }

    const platform = c.node_multi_isolate_platform_create(4) orelse return error.Platform;
    defer c.node_multi_isolate_platform_free(platform);
    c.v8_initialize_platform(platform);
    defer c.v8_dispose_platform();
    _ = c.v8_initialize();
    defer _ = c.v8_dispose();
    performance_timing_lap("v8 platform + initialize");

    const setup = c.node_common_environment_setup_create(platform, result) orelse return error.CouldNotCreateSetup;
    defer c.node_common_environment_setup_free(setup);
    performance_timing_lap("env setup create");

    const isolate = c.node_common_environment_setup_isolate(setup);
    const env = c.node_common_environment_setup_env(setup);

    // Enter the v8 scopes. defers run LIFO, so they tear down in reverse order:
    // context_scope -> handle_scope -> isolate_scope -> locker.
    const locker = c.v8_locker_new(isolate);
    defer c.v8_locker_free(locker);
    const isolate_scope = c.v8_isolate_scope_new(isolate);
    defer c.v8_isolate_scope_free(isolate_scope);
    const handle_scope = c.v8_handle_scope_new(isolate);
    defer c.v8_handle_scope_free(handle_scope);

    const context = c.node_common_environment_setup_context(setup);
    defer c.v8_local_context_free(context);
    const context_scope = c.v8_context_scope_new(context);
    defer c.v8_context_scope_free(context_scope);

    // Install native test()/expect() globals on the context before running
    // anything, so they're present the moment user tests evaluate.
    const global = c.v8_context_global(context);
    defer c.v8_local_value_free(global);
    const test_fn = c.v8_function_new(context, testCallback, null);
    defer c.v8_local_value_free(test_fn);
    c.v8_object_set(context, global, "test", test_fn);
    const expect_fn = c.v8_function_new(context, &expectCallback, null);
    defer c.v8_local_value_free(expect_fn);
    c.v8_object_set(context, global, "expect", expect_fn);
    performance_timing_lap("scopes + globals install");

    var code_to_bundle: std.ArrayList(u8) = .empty;

    const cwd = try std.Io.Dir.cwd().openDir(io, ".", .{ .iterate = true });
    var walker = try cwd.walkSelectively(arena);
    while (try walker.next(io)) |entry| {
        if (entry.kind == .directory) {
            if (std.mem.eql(u8, entry.basename, "node_modules")) continue;
            if (std.mem.eql(u8, entry.basename, "zig-out")) continue;
            if (std.mem.eql(u8, entry.basename, ".zig-cache")) continue;
            if (std.mem.eql(u8, entry.basename, ".git")) continue;
            if (std.mem.eql(u8, entry.basename, ".next")) continue;
            if (std.mem.eql(u8, entry.basename, "dist")) continue;
            try walker.enter(io, entry);
            continue;
        }
        if (std.mem.endsWith(u8, entry.path, ".test.js")) {
            try code_to_bundle.print(arena, "import './{s}'\n", .{entry.path});
        }
    }

    const entry_z = try arena.dupeZ(u8, code_to_bundle.items);
    const cwd_path = try std.process.currentPathAlloc(io, arena);
    performance_timing_lap("collect test files");

    var ok: c_int = 0;
    const bundled = esb.esbuild_bundle(entry_z.ptr, cwd_path.ptr, &ok);
    defer esb.esbuild_free(bundled);
    if (ok != 1) {
        std.debug.print("bundle failed:\n{s}\n", .{std.mem.span(bundled)});
        return error.BundleFailed;
    }
    performance_timing_lap("esbuild bundle");

    if (!c.node_load_environment_module(env, bundled, "file:///testa-entry.mjs")) {
        return error.CouldNotLoadEnvironmentModule;
    }
    performance_timing_lap("load module + run tests");

    const loop_code = c.node_spin_event_loop(env);
    _ = c.node_stop(env);
    performance_timing_lap("spin event loop");

    var buffer: [128]u8 = undefined;
    var stderr = std.Io.File.stderr().writer(io, &buffer);
    try stderr.interface.print("\n{d} passed, {d} failed\n", .{ passed_tests, failed_tests });
    if (timing_on) {
        try stderr.interface.print("\n[timing]\n", .{});
        for (timings[0..timings_n]) |t| {
            try stderr.interface.print("  {s}: {f}\n", .{ t.label, t.d });
        }
    }
    try stderr.flush();
    // Exit straight to a status code: a failing test is a normal outcome, not
    // a runner error, so we don't want Zig's error-return panic/trace here.
    if (loop_code != 0) {
        std.process.exit(if (loop_code > 0 and loop_code < 256) @intCast(loop_code) else 1);
    } else if (failed_tests > 0) {
        std.process.exit(1);
    }
}
