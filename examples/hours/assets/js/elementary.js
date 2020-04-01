export default (appUrl, appEffects) => {
    const config = (window.elementary || {})
    const state = {}

    function sleep(sleepDuration) {
        var now = new Date().getTime();
        while (new Date().getTime() < now + sleepDuration) { /* do nothing */ }
    }

    function elapsed(t1, t2) {
        return t2.getTime() - t1.getTime();
    }

    function tc(fun) {
        const t1 = new Date();
        const r = fun();
        const t2 = new Date();
        return { millis: elapsed(t1, t2), res: r };
    }

    function typeOf(data) {
        if (!data) return "undefined";
        var t = typeof (data);
        if (t === 'object') {
            return (Array.isArray(data)) ? "list" : "object";
        } else return (t === 'string') ? "text" : t;
    }

    function error(spec, ctx, reason) {
        return { err: { spec, ctx, reason } };
    }

    function fmt(pattern, args) {
        return Mustache.render(pattern, args)
    };

    function flatten(arr) {
        return [].concat(...arr)
    }

    function encodeObject(spec, ctx) {
        var out = {};
        for (var k in spec.object) {
            if (spec.object.hasOwnProperty(k)) {
                const { err, value } = encode(spec.object[k], ctx);
                if (err) return error(spec.object[k], ctx, err);
                out[k] = value;
            }
        }
        return { value: out };
    }

    function encodeKey(spec, ctx) {
        if (!ctx) return error(spec, ctx, "Missing context");
        if (!spec.key.length) return error(spec, ctx, "Invalid key spec");
        if (spec.key === "@") return { value: ctx };
        var paths = spec.key.substring(1).split(".");
        var value = ctx;
        for (var i = 0; i < paths.length; i++) {
            var path = paths[i];
            if (!value.hasOwnProperty(path)) return error(path, value, "Missing key");
            value = value[path];
        }
        return { value };
    }

    function encodeList(items, ctx) {
        var values = [];
        for (var i = 0; i < items.length; i++) {
            var { err, value } = encode(items[i], ctx);
            if (err) return error(items[i], ctx, err);
            values[i] = value;
        }
        return { value: values };
    }

    //function asKeyPath(spec, out) {
    //    if (spec.key) out.push(spec.key)
    //    if (!spec.in) {
    //        out.reverse();
    //        return out.join(".");
    //    } else {
    //        return asKeyPath(spec.in, out);
    //    }
    //}

    //function encodeI18n(spec, data, ctx) {
    //    var lang = data.lang || 'en';
    //    if (spec.lang) {
    //        var {err, value} = encode(spec.lang, data, ctx);
    //        if (err) return error(spec, data, err);
    //        lang = value;
    //    }
    //    var {err, value} = encode(spec.i18n, data, ctx);
    //    if (err) {
    //        var pathSpec = { key: lang, in: spec.i18n };
    //        return { value: "??" + asKeyPath(pathSpec, [])+ "??" };
    //    } else {
    //        var value = value[lang];
    //        if (value) {
    //            return {value};
    //        } else {
    //            var pathSpec = { key: lang, in: spec.i18n };
    //            return { value: "??" + asKeyPath(pathSpec, [])+ "??" };
    //        }
    //    }
    //}

    function encodeFormat(spec, ctx) {
        var { err, value } = encode(spec.params || "@", ctx);
        if (err) return error(spec, ctx, err);
        return { value: fmt(spec.format, value) };
    }

    function encodeFormatDate(spec, ctx) {
        var { pattern, date } = spec.format_date;
        var { err, value } = encode(pattern, ctx);
        if (err) return error(spec, ctx, err);
        var pattern = value;
        var { err, value } = encode(date, ctx);
        if (err) return error(spec, ctx, err);
        switch (pattern) {
            case "relative":
                return { value: moment(value).fromNow() };
            default:
                return { value: moment(value).format(pattern) };
        }
    }

    function encodeMaybe(spec, ctx) {
        const { err, value } = encode(spec.maybe, ctx);
        return { value };
    }

    function encodeEqual(spec, ctx) {
        if (!spec.equal.length) return { value: false };
        var { err, value } = encode(spec.equal[0], ctx);
        if (err) return error(spec, ctx, err);
        var expected = value;
        for (var i = 1; i < spec.equal.length; i++) {
            var s = spec.equal[i];
            var { err, value } = encode(s, ctx);
            if (err) return error(spec, ctx, err);
            if (value != expected) return { value: false };
        }

        return { value: true };
    }

    function encodeAnd(spec, ctx) {
        if (!spec.and) return { value: false };
        for (var i = 0; i < spec.and.length; i++) {
            var s = spec.and[i];
            var { err, value } = encode(s, ctx);
            if (err) return error(spec, ctx, err);
            if (!value) return { value: false }
        }
        return { value: true };
    }

    function encodeOr(spec, ctx) {
        if (!spec.or) return { value: false };
        for (var i = 0; i < spec.or.length; i++) {
            var s = spec.or[i];
            var { err, value } = encode(s, ctx);
            if (err) return error(spec, ctx, err);
            if (value) return { value: true }
        }
        return { value: false };
    }

    function encodeIsSet(spec, ctx) {
        if (!ctx) return error(spec, ctx, "Missing context");
        var { err, value } = encode(spec.is_set, ctx);
        if (err) return error(spec, ctx, err);
        if (!value) return { value: false };
        switch (typeof (value)) {
            case 'string':
                return value.length ? { value: true } : { value: false };
        }
        return { value: true }
    }

    function encodeNot(spec, ctx) {
        var { err, value } = encode(spec.not, ctx);
        if (err) return error(spec, ctx, err);
        if (!typeof (value) === 'boolean') return error(spec, ctx, {
            value: value,
            reason: "not_a_boolean"
        });
        return { value: !value };
    }

    function encodeEither(spec, ctx) {
        if (!spec.either.length) return error(spec, ctx, "Not enough clauses");
        for (var i = 0; i < spec.either.length; i++) {
            var s = spec.either[i];
            if (!s.when) {
                s = s.then || s;
                var { err, value } = encode(s, ctx);
                if (err) return error(s, ctx, err);
                return { value };
            }

            var { err, value } = encode(s.when, ctx);
            if (err) return error(s.when, ctx, err);
            if (value) {
                s = s.then || s;
                var { err, value } = encode(s, ctx);
                if (err) return error(s, ctx, err);
                return { value };
            }
        }
        return error(spec, data, "No clause matched");
    }

    function encodeUsingEncoder(spec, ctx) {
        var { err, value } = encode(spec.encoder, ctx);
        if (err) return error(spec, ctx, err);
        var encName = value;
        var enc = state.app.encoders[encName];
        if (!enc) return error(spec, ctx, "No such encoder: " + encName);
        var encoderCtx = ctx;
        if (spec.params) {
            var { err, value } = encode(spec.params, ctx);
            if (err) return error(spec.params, ctx, err);
            encoderCtx = value;
        }
        return encode(enc, encoderCtx);
    }

    //function encodeUsingExpression(spec, data, ctx) {
    //    var {err, value} = encode(spec.encode, data, ctx);
    //    if (err) return error(spec, data, err);
    //    var s0 = value;
    //    if (spec.as) {
    //        var {err, value} = encode(spec.as, data, ctx);
    //        var s = {}
    //        s[value] = s0;
    //    } else {
    //        var s = s0;
    //    }
    //    return encode(spec["with"], s, ctx);
    //}

    function encodeTimestamp(spec, ctx) {
        return encode({
            format_date: {
                pattern: spec.timestamp.format,
                date: spec.timestamp.value
            }
        }, ctx);
    }

    function encodeText(spec, ctx) {
        var { err, value } = encode(spec.text, ctx);
        if (err) return error(spec, ctx, err);
        return { value: '' + value };
    }

    function encodePercent(spec, ctx) {
        var { err, value } = encode(spec.percent.num, ctx);
        if (err) return error(spec, ctx, err);
        var num = value;
        var { err, value } = encode(spec.percent.den, ctx);
        if (err) return error(spec, ctx, err);
        var den = value;
        if (!den) return { value: 0 };
        return { value: Math.floor(num / den) * 100 };
    }

    //function encodeAny(spec, ctx) {
    //    if (spec.any === 'object' && typeof(data) === 'object' && !Array.isArray(data)) {
    //        return {value: ctx};
    //    }

    //    return error(spec, data, "any spec not supported");
    //}

    //function encodeExpression(spec, data, ctx) {
    //    return {value: spec.expression};
    //}

    //function encodeEncoded(spec, data, ctx) {
    //    var {err, value} = encode(spec.encoded, data, ctx);
    //    if (err) return error(spec, data, err);
    //    return encode(value, data, ctx);
    //}

    //function encodeIterate(spec, data, ctx) {
    //    var {err, value} = encode(spec.iterate.source, data, ctx);
    //    if (err) return error(spec, data, err);
    //    var source = value;
    //    var out = [];
    //    var filterFn = spec.iterate.filter === 'none' ?
    //        function(i, ctx) {
    //            return {value: true};
    //        }
    //        :
    //        function(i, ctx) {
    //            return decode(spec.iterate.filter, i, ctx);
    //        };
    //    var itemFn = spec.iterate.as === 'none' ?
    //        function(i) {
    //            return i;
    //        }
    //        :
    //        function(i) {
    //            var obj = {};
    //            obj[spec.iterate.as] = i;
    //            return obj;
    //        }

    //    var {err, value} = encode(spec.iterate.context, data, ctx);
    //    if (err) return error(spec, data, err);
    //    var context = {context: value};
    //    for (var i=0; i<source.length; i++) {
    //        var {err, value} = filterFn(source[i], context);
    //        if (!err) {
    //            var item = itemFn(source[i]);
    //            var {err, value} = encode(spec.iterate.dest, Object.assign(context, item), ctx);
    //            if (err) return error(spec, data, err);
    //            out[i] = value;
    //        }
    //    }
    //    return {value: out};
    //}

    function encodeMergedList(spec, ctx) {
        var lists = [];
        for (var i = 0; i < spec.merged_list.length; i++) {
            var { err, value } = encode(spec.merged_list[i], ctx);
            if (err) return error(spec, ctx, err);
            lists[i] = value;
        }
        return { value: flatten(lists) }
    }

    function encodeMergedObject(spec, ctx) {
        var objs = [];
        for (var i = 0; i < spec.merge.length; i++) {
            var { err, value } = encode(spec.merge[i], ctx);
            if (err) return error(spec, ctx, err);
            objs[i] = value;
        }
        return { value: Object.assign({}, ...objs) }
    }

    function encodePrettify(spec, ctx) {
        var { err, value } = encode(spec.prettify, ctx);
        if (err) return error(spec, ctx, err);
        return { value: JSON.stringify(value, null, 2) };
    }

    function encodePercent(spec, ctx) {
        var { err, value } = encode(spec.percent.den, ctx);
        if (err) return error(spec, ctx, err);
        if (!value) return error(spec, data, "denominator is zero");
        var den = value;
        var { err, value } = encode(spec.percent.num, ctx);
        if (err) return error(spec, ctx, err);
        return { value: Math.round(100 * value / den) };
    }

    function encodeSum(spec, ctx) {
        var { err, value } = encodeList(spec.sum, ctx);
        if (err) return error(spec, ctx, err);
        if (!value || !value.length) return { value: 0 };
        var sum = 0;
        for (var i = 0; i < value.length; i++) {
            var item = value[i];
            if (typeof (item) != 'number') return error(spec, item, "not_a_number");
            sum += item;
        }
        return { value: sum };
    }

    function encodeDivide(spec, ctx) {
        var { err, value } = encodeList(spec.divide, ctx);
        if (err) return error(spec, ctx, err);
        if (!value || value.length < 2) return error(spec, item, "not_enough_arguments");
        var num = value[0];
        for (var i = 1; i < value.length; i++) {
            if (typeof (value[i]) != 'number') return error(spec, value, "not_a_number");
            if (!value[i]) return error(spec, value, "division_by_zero");
            num = num / value[i];
        }
        if (!spec.hasOwnProperty("decimals")) return { value: num };
        return { value: num.toFixed(spec.decimals) };
    }

    var sizeEncoders = {
        "undefined": (d) => { return 0 },
        "list": (d) => { return d.length },
        "object": (d) => { return Object.keys(d).length },
        "string": (d) => { return d.length },
        "number": (d) => { return d.number },
        "boolean": (d) => { return 0 }
    }

    function encodeSizeOf(spec, ctx) {
        var { err, value } = encode(spec.size_of, ctx);
        if (err) return error(spec, ctx, err);
        var e = sizeEncoders[typeOf(value)];
        if (!e) return error(spec, value, "cannot_encode_size");
        var s = e(value);
        return { value: s };
    }

    function encodeLowerCase(spec, ctx) {
        var { err, value } = encode(spec.lowercase, ctx);
        if (err) return error(spec, ctx, err);
        switch (typeof (value)) {
            case "string":
                return { value: value.toLowerCase() };
            default:
                return error(spec, value, "not_a_string");
        }
    }

    function encodeUpperCase(spec, ctx) {
        var { err, value } = encode(spec.uppercase, ctx);
        if (err) return error(spec, ctx, err);
        switch (typeof (value)) {
            case "string":
                return { value: value.toUpperCase() };
            default:
                return error(spec, value, "not_a_string");
        }
    }

    function encodeCapitalize(spec, ctx) {
        var { err, value } = encode(spec.capitalize, ctx);
        if (err) return error(spec, ctx, err);
        switch (typeof (value)) {
            case "string":
                return { value: value.charAt(0).toUpperCase() + value.slice(1) };
            default:
                return error(spec, value, "not_a_string");
        }
    }

    function encodeOneOf(spec, ctx) {
        for (var i = 0; i < spec.one_of.length; i++) {
            var { err, value } = encode(spec.one_of[i], ctx);
            if (!err && value) {
                return { value: value }
            }
        }
        return error(spec, ctx, "no_valid_non_null_expression_found");
    }


    function encodeCmd(spec, ctx) {
        var { err, value } = encode(spec.effect, ctx);
        if (err) return error(spec, ctx, err);
        var cmd = { effect: value };
        if (spec.encoder) {
            var { err, value } = encode(spec.encoder, ctx);
            if (err) return error(spec.encoder, ctx, err);
            cmd.encoder = value;
        }
        return { value: cmd };
    }

    function encodeSplit(spec, ctx) {
        var { err, value } = encode(spec.using, ctx);
        if (err) return error(spec, ctx, err);
        var sep = value;
        var { err, value } = encode(spec.split, ctx);
        if (err) return error(spec, ctx, err);
        switch (typeof (value)) {
            case "string":
                return { value: value.split(sep) };
            default:
                return error(spec, value, "not_a_string");
        }
    }

    function encodeJoin(spec, ctx) {
        var { err, value } = encode(spec.using, ctx);
        if (err) return error(spec, ctx, err);
        var sep = value;
        var { err, value } = encode(spec.join, ctx);
        if (err) return error(spec, ctx, err);
        if (!Array.isArray(value)) return error(spec, value, "not_a_list");
        return { value: value.join(sep) };
    }

    function encodeHead(spec, ctx) {
        var { err, value } = encode(spec.head, ctx);
        if (err) return error(spec, ctx, err);
        if (!Array.isArray(value)) return error(spec, value, "not_a_list");
        const [head, _] = value;
        if (!head) return error(spec, value, "empty_list");
        return { value: head };

    }

    function encodeTail(spec, ctx) {
        var { err, value } = encode(spec.tail, ctx);
        if (err) return error(spec, ctx, err);
        if (!Array.isArray(value)) return error(spec, value, "not_a_list");
        const [_, ...tail] = value;
        if (!tail) return error(spec, value, "empty_list");
        return { value: tail };
    }

    function encodeLast(spec, ctx) {
        var { err, value } = encode(spec.last, ctx);
        if (err) return error(spec, ctx, err);
        if (!Array.isArray(value)) return error(spec, value, "not_a_list");
        if (!value.length) return error(spec, value, "empty_list");
        return { value: value[value.length - 1] };
    }

    function encodeChar(spec, ctx) {
        var { err, value } = encode(spec['char'], ctx);
        if (err) return error(spec, ctx, err);
        var c = value;
        var { err, value } = encode(spec['in'], ctx);
        if (err) return error(spec, ctx, err);
        return { value: value.charAt(c) };
    }

    function encodeGreaterThan(spec, ctx) {
        if (spec.greater_than.length < 2) return error(spec, ctx, "not_enough_arguments");
        var { err, value } = encode(spec.greater_than[0], ctx);
        if (err) return error(spec, ctx, err);
        var v1 = value;
        var { err, value } = encode(spec.greater_than[1], ctx);
        if (err) return error(spec, ctx, err);
        return { value: v1 > value };
    }

    function encodeLowerThan(spec, ctx) {
        if (spec.lower_than.length < 2) return error(spec, ctx, "not_enough_arguments");
        var { err, value } = encode(spec.lower_than[0], ctx);
        if (err) return error(spec, ctx, err);
        var v1 = value;
        var { err, value } = encode(spec.lower_than[1], ctx);
        if (err) return error(spec, ctx, err);
        return { value: v1 < value };
    }

    function encodeRegex(spec, ctx) {
        var { err, value } = encode(spec.in, ctx);
        if (err) return error(spec, ctx, err);
        return { value: value.match(spec.regex) != null };
    }

    function encodeSwitch(spec, ctx) {
        var { err, value } = encode(spec["switch"], ctx);
        if (err) return error(spec, ctx, err);
        var clause = spec["case"][value];
        if (!clause) {
            return error(spec, ctx, "no clause matched");
        }
        var { err, value } = encode(clause, ctx);
        if (err) return error(clause, ctx, err);
        return { value };
    }

    function encodePipeline(spec, ctx) {
        var specs = spec.pipeline;
        if (!Array.isArray(specs)) return error(spec, ctx, "not a list of specs");
        var value = ctx;
        for (var i = 0; i < specs.length; i++) {
            var { err, value } = encode(specs[i], value);
            if (err) return error(specs[i], value, err);
        }
        return { value };
    }

    function encodeFilter(spec, ctx) {
        var { err, value } = encode(spec.filter, ctx);
        if (err) return error(spec.filter, ctx, err);
        if (!Array.isArray(value)) return error(spec.filter, value, "Not a list");
        var items = value;

        var out = [];
        for (var i = 0; i < items.length; i++) {
            var { err, decoded } = decode(spec.with, items[i], ctx);
            if (!err && decoded) {
                out.push(items[i]);
            }
        }
        return { value: out };
    }

    function encode(spec, ctx) {
        if (spec == undefined || spec == null) return error(spec, ctx, "Missing encoding spec");
        switch (typeof (spec)) {
            case "object":
                if (spec.hasOwnProperty("text")) return encodeText(spec, ctx);
                if (spec.hasOwnProperty("char")) return encodeChar(spec, ctx);
                if (Array.isArray(spec)) return encodeList(spec, ctx);
                if (spec.object) return encodeObject(spec, ctx);
                if (spec.hasOwnProperty("switch")) return encodeSwitch(spec, ctx);
                //if (spec.key) return encodeKey(spec, ctx);
                //if (spec.key_path) return encodeKeyPath(spec, ctx);
                //if (spec.i18n) return encodeI18n(spec, ctx);
                if (spec.format) return encodeFormat(spec, ctx);
                if (spec.format_date) return encodeFormatDate(spec, ctx);
                if (spec.timestamp) return encodeTimestamp(spec, ctx);
                if (spec.maybe) return encodeMaybe(spec, ctx);
                if (spec.equal) return encodeEqual(spec, ctx);
                if (spec.either) return encodeEither(spec, ctx);
                if (spec.one_of) return encodeOneOf(spec, ctx);
                if (spec.effect) return encodeCmd(spec, ctx);
                if (spec.encoder) return encodeUsingEncoder(spec, ctx);
                //if (spec.encode) return encodeUsingExpression(spec, ctx);
                if (spec.percent) return encodePercent(spec, ctx);
                if (spec.is_set) return encodeIsSet(spec, ctx);
                if (spec.not) return encodeNot(spec, ctx);
                if (spec.and) return encodeAnd(spec, ctx);
                if (spec.or) return encodeOr(spec, ctx);
                if (spec.any) return encodeAny(spec, ctx);
                if (spec.head) return encodeHead(spec, ctx);
                if (spec.tail) return encodeTail(spec, ctx);
                if (spec.last) return encodeLast(spec, ctx);
                if (spec.split) return encodeSplit(spec, ctx);
                if (spec.join) return encodeJoin(spec, ctx);
                if (spec.merged_list) return encodeMergedList(spec, ctx);
                if (spec.merge) return encodeMergedObject(spec, ctx);
                if (spec.iterate) return encodeIterate(spec, ctx);
                //if (spec.expression) return encodeExpression(spec, ctx);
                //if (spec.encoded) return encodeEncoded(spec, ctx);
                if (spec.prettify) return encodePrettify(spec, ctx);
                if (spec.percent) return encodePercent(spec, ctx);
                if (spec.divide) return encodeDivide(spec, ctx);
                if (spec.sum) return encodeSum(spec, ctx);
                if (spec.size_of) return encodeSizeOf(spec, ctx);
                if (spec.lowercase) return encodeLowerCase(spec, ctx);
                if (spec.uppercase) return encodeUpperCase(spec, ctx);
                if (spec.capitalize) return encodeCapitalize(spec, ctx);
                if (spec.greater_than) return encodeGreaterThan(spec, ctx);
                if (spec.lower_than) return encodeLowerThan(spec, ctx);
                if (spec.regex) return encodeRegex(spec, ctx);
                if (spec.pipeline) return encodePipeline(spec, ctx);
                if (spec.filter) return encodeFilter(spec, ctx);
                if (!Object.keys(spec).length) return { value: {} };
                return encodeObject({ object: spec }, ctx)
            case "string":
                if (spec == "@") return { value: ctx };
                if (spec.startsWith("@")) return encodeKey({ key: spec }, ctx);
                return { value: spec };
            case "boolean":
                return { value: spec };
            case "number":
                return { value: spec };
        }
    }

    function decodeObject(spec, data, ctx) {
        if (!data || typeof (data) != 'object') return error(spec, data, "no_match");
        var out = {};
        for (var k in spec.object) {
            if (spec.object.hasOwnProperty(k)) {
                var keySpec = spec.object[k];
                var { err, decoded } = decode(keySpec, data[k], ctx);
                if (err) return error(keySpec, data[k], err);
                out[k] = decoded;
            }
        }
        return { decoded: out };
    }

    function decodeOtherThan(spec, data, ctx) {
        var { err, value } = encode(spec.other_than, ctx);
        if (err) return error(spec, data, err);
        if (data != value) return { decoded: data };
        return error(spec, data, "no_match");
    }

    function no_match(spec, data) {
        return error(spec, data, "no_match");
    }

    function decodeType(spec, data, expected) {
        return typeof (data) === expected ?
            { decoded: data } : no_match(spec, data)
    }

    var anyConditions = {
        "text": (spec, data) => {
            return decodeType(spec, data, 'string');
        },
        "number": (spec, data) => {
            return decodeType(spec, data, "number");
        },
        "boolean": (spec, data) => {
            return decodeType(spec, data, "boolean");
        },
        "object": (spec, data) => {
            return decodeType(spec, data, "object");
        },
        "list": (spec, data) => {
            return Array.isArray(data) ?
                { decoded: data } : no_match(spec, data)
        },
        "file": (spec, data) => {
            if (data && data.length && data.item) {
                var first = data.item(0);
                return {
                    decoded: {
                        name: first.name,
                        type: first.type,
                        size: first.size,
                        file: first
                    }
                };
            }
            return no_match(spec, data);
        }
    }

    function decodeAny(spec, data, ctx) {
        if (data == undefined || data == null) return error(spec, data, "no_data");
        var d = anyConditions[spec.any];
        if (!d) return error(spec, data, "unknown_any_condition");
        return d(spec, data);
    }

    function decodeList(spec, data, ctx) {
        if (!Array.isArray(data)) return error(spec, data, "no_match");
        if (Array.isArray(spec.list)) {
            var out = [];
            var itemSpec;
            for (var i = 0; i < spec.list.length; i++) {
                var item = data[i];
                itemSpec = spec.list[i];
                var { err, decoded } = decode(itemSpec, item, ctx);
                if (err) return error(spec, data, err);
                out.push(decoded);
            }
            return { decoded: out };
        } else {
            var out = [];
            var itemSpec = spec.list;
            for (var i = 0; i < data.length; i++) {
                var item = data[i];
                var { err, decoded } = decode(itemSpec, item, ctx);
                if (err) return error(spec, data, err);
                out.push(decoded);
            }
            return { decoded: out };
        }
    }

    function decodeOne(spec, data, ctx) {
        function _(i) {
            if (i == spec.one_of.length) return error(spec, data, "no_match")
            var s = spec.one_of[i];
            var { err, decoded } = decode(s, data, ctx);
            if (err) return _(i + 1);
            return { decoded };
        }
        return _(0);
    }


    function decodeJson(spec, data, ctx) {
        try {
            return { value: JSON.parse(spec.json) };
        } catch (e) {
            return { err: { json: spec.json, error: e } };
        }
    }

    function decodeSize(spec, data) {
        var { err, value } = encode(spec.size, data);
        if (err) return error(spec, data, err);
        switch (typeof (data)) {
            case 'object':
                if (Array.isArray(data) && data.length == value) return { decoded: data };
                if (Object.keys(data).length == value) return { decoded: data };
            case 'string':
                if (data && data.length == value) return { decoded: data };
        }
        return error(spec, data, "no_match");
    };

    function decodeKey(spec, data, ctx) {
        var { err, value } = encode(spec, ctx);
        if (err) return error(spec, data, err);
        return decode(value, data, ctx)
    }

    function decodeText(spec, data, ctx) {
        var { err, value } = encode(spec, ctx);
        if (err) return error(spec, ctx, err);
        return value === data ? { decoded: data } : error(spec, data, "no_match");
    }

    function decodeLike(spec, data, ctx) {
        var { err, value } = encode(spec.like, ctx);
        if (err) return error(spec, data, err);
        var regex = new RegExp(value, 'i');
        return data.match(regex) ? { decoded: data } : error(spec, data, "no_match");
    }

    function decodeSame(spec, data, ctx) {
        return spec === data ? { deocded: data } : error(spec, data, "no_match");
    }

    function decode(spec, data, ctx) {
        switch (typeof (spec)) {
            case "object":
                if (spec.hasOwnProperty("text")) return decode(spec.text, data, ctx);
                if (spec.key) return decodeKey(spec, data, ctx);
                if (spec.object) return decodeObject(spec, data, ctx);
                if (spec.any) return decodeAny(spec, data, ctx);
                if (spec.list) return decodeList(spec, data, ctx);
                if (spec.other_than) return decodeOtherThan(spec, data, ctx);
                if (spec.one_of) return decodeOne(spec, data, ctx);
                if (spec.json) return decodeJson(spec, data, ctx);
                if (spec.size) return decodeSize(spec, data, ctx);
                if (spec.like) return decodeLike(spec, data, ctx);
                if (Array.isArray(spec)) return decodeList({ list: spec }, data, ctx);
                return decodeObject({ object: spec }, data, ctx);
            case "string":
                return decodeText(spec, data, ctx);
            default:
                return decodeSame(spec, data, ctx);
        }
    }

    function tryDecoders(data, decs) {
        if (!decs || !decs.length) return error(null, data, "no_decoders");
        for (var i = 0; i < decs.length; i++) {
            var d = decs[i];
            var spec = d.spec;
            const { err, decoded } = decode(spec, data, state.model)
            if (!err && decoded) return { decoded: { msg: d.msg, data: decoded } };
        }
        return error(null, data, "all_decoders_failed");
    }

    function tryAllDecoders(effect, data, decoders) {
        var { err, decoded } = tryDecoders(data, decoders[effect]);
        if (!err) return { decoded };
        if (err) return error(null, data, "all_decoders_failed");
    }

    function assetUrl(baseUrl, name) {
        return baseUrl + 'js/' + name + '.js';
    }

    // function encodeCmds(spec, data) {
    //     switch(typeof(spec)) {
    //         case "object":
    //             if (Array.isArray(spec)) {
    //                 var encoded = [];
    //                 for (var i=0; i<spec.length; i++) {
    //                     var cmd = { effect: spec[i].effect };
    //                     if (spec[i].hasOwnProperty("encoder")) {
    //                         var {err, value} = encode(spec[i].encoder, data, {});
    //                         if (err) return error(spec, data, "unsupported_encoder");
    //                         cmd.encoder = value;
    //                     }
    //                     encoded[i] = cmd;
    //                 }
    //                 return {value: encoded};
    //             } else {
    //                 return encode(spec, data, {})
    //             }
    //         default:
    //             return error(spec, data, "unsupported_cmds")
    //     }
    // }

    function encodeCmds(spec, data) {
        var cmds = [];
        var effects = Object.getOwnPropertyNames(spec);
        for (var i = 0; i < effects.length; i++) {
            var eff = effects[i];
            var enc = spec[eff];
            if (isEmpty(enc)) {
                cmds.push({ effect: eff });
            } else {
                var { err, value } = encode(enc, data, {});
                if (err) return error(enc, data, "unsupported_encoder");
                cmds.push({
                    effect: eff,
                    encoder: value
                });
            }
        }

        return { value: cmds };
    }

    function isEmpty(obj) {
        if (!obj || (obj.length && obj.length == 0)) return true;
        for (var x in obj) { return false; }
        return true;
    }

    function withSettings(m) {
        return Object.assign({}, m, state.app.settings);
    }

    function applyCmds(encoders, effects, cmds, m2) {
        var { err, value } = encodeCmds(cmds, m2);
        if (err) return error(cmds, m2, err);
        value.forEach((cmd) => {
            const { effect, encoder } = cmd;
            const eff = effects[effect];
            if (!eff) {
                console.error("No such effect", cmd);
                return;
            }

            var enc = null;
            if (encoder) {
                enc = encoders[encoder];
                if (!enc) {
                    console.error("No such encoder", cmd);
                    return;
                }
            }

            setTimeout(() => {
                eff(encoders, enc, withSettings(m2));
            }, 0);
        });
    }

    function withWhere(spec, data) {
        if (!spec.where) return { value: data };
        var { err, value } = encode(spec.where, data);
        if (err) return error(spec.where, data, err);
        return { value: Object.assign(data, value) };
    }

    function log(msg, data) {
        if (state.app.settings.debug) console.log(msg, data);
    }

    function selectUpdate(msg, update, ctx) {
        var clauses = update[msg];
        if (clauses && !Array.isArray(clauses)) return { spec: clauses };
        if (!clauses || !clauses.length) return error(msg, ctx, "no_update_implemented");
        for (var i = 0; i < clauses.length; i++) {
            var c = clauses[i];
            if (!c.condition) return { spec: c };
            const { err, value } = encode(c.condition, ctx);
            log("[core] condition", {
                condition: c.condition,
                context: ctx,
                error: err,
                value: value
            });
            if (err) return error(c.condition, model, err);
            if (value) return { spec: c };
        }
        return error(clauses, ctx, "all_conditions_failed");
    }

    function _update(ev) {
        const t0 = new Date();
        if (!ev.effect) {
            console.error("[core] no 'effect' key in event", ev);
            return;
        }
        var effect = ev.effect;
        delete ev.effect;
        const { encoders, effects, decoders, update } = state.app;
        var { err, decoded } = tryAllDecoders(effect, ev, decoders);
        if (err) {
            console.error("Decode error", err);
            return;
        }
        const { msg, data } = decoded;
        log("[core] decoded", decoded);
        const t1 = new Date();
        var ctx = {
            model: state.model,
            data: data
        };
        var { err, spec } = selectUpdate(msg, update, ctx);
        if (err) {
            console.error("Select update Uerror", err);
            return;
        }
        var { err, value } = withWhere(spec, ctx);
        if (err) {
            console.error("Where error", err);
            return;
        }
        ctx = value;
        log("[core] update spec", { spec, ctx });
        var { err, value } = encode(spec, ctx);
        if (err) {
            console.error("Encode new model error", err);
            return err;
        }
        var { model, cmds } = value;
        Object.assign(state.model, model);
        log("[core] new model", state.model);
        const t2 = new Date();
        if (spec.cmds) applyCmds(encoders, state.effects, cmds, state.model);
        const t3 = new Date();
        if (state.app.settings.telemetry) {
            console.log("[core]"
                + "[decode " + elapsed(t0, t1) + "ms]"
                + "[update " + elapsed(t1, t2) + "ms]"
                + "[cmds " + elapsed(t2, t3) + "ms]");
        }
    }

    function update(ev) {
        setTimeout(function () {
            _update(ev);
        }, 0)
    }

    function encodeModelWithDefault(spec, defaultValue, ctx) {
        if (!spec) return { value: defaultValue }
        return encode(spec, ctx);
    }

    function init(app) {
        const { init } = app;
        const { model, cmds } = init;

        const t0 = new Date();
        const { err, value } = encodeModelWithDefault(model, {}, withSettings({}))
        if (err) {
            console.error("(init) cannot encode model", err);
        } else {
            state.model = value;
            const t1 = new Date();
            applyCmds(app.encoders, state.effects, cmds, state.model);
            const t2 = new Date();
            if (state.app.settings.telemetry) {
                console.log("[core]"
                    + "[init " + elapsed(t0, t1) + "ms]"
                    + "[cmds " + elapsed(t1, t2) + "ms]");
            }
        }
    }


    function indexedDecoders(effects, index) {
        var index = {};
        for (var k in effects) {
            if (effects.hasOwnProperty(k)) {
                var decs = effects[k];
                for (var dec in decs) {
                    if (decs.hasOwnProperty(dec)) {
                        var d = decs[dec];
                        var effSpec = d.object && d.object.effect ? d.object.effect : k;
                        var { err, value } = encode(effSpec, {});
                        if (err) return { err: err };
                        var eff = value;
                        if (!index[eff]) index[eff] = [];
                        index[eff].push({ msg: dec, spec: d });
                    }
                }
            }
        }
        return { value: index };
    }

    function compiledApp(app) {
        var { err, value } = indexedDecoders(app.decoders);
        if (err) {
            console.error("(decoders) failed to index decoders", err);
            return;
        }
        app.decoders = value;
        app.settings = app.settings || {};
        return app;
    }

    function effects(mods, next) {
        const out = {};
        for (var n in mods) {
            if (mods.hasOwnProperty(n)) {
                const effSettings = (state.app.effects && state.app.effects[n]) ?
                    (state.app.effects[n].settings || {}) : {};
                const settings = Object.assign({}, state.app.settings, effSettings);
                const mod = mods[n];
                const send = mod(n, settings, {
                    encode,
                    decode,
                    update,
                    tc
                });
                if (send instanceof Function) {
                    out[n] = send;
                } else {
                    console.warn('effect ' + n + ' is not returning a send function', send);
                }
            }
        }
        next(out);
    }

    function app(url, next) {
        fetch(url)
            .then((mod) => {
                return mod.json();
            })
            .then(next)
            .catch((err) => {
                console.error("app error", err);
            });
    };

    app(appUrl, function (app) {
        state.app = compiledApp(app);
        if (state.app.settings.debug) console.log(app);
        effects(appEffects, (effs) => {
            state.effects = effs;
            init(app);
        });
    });

};
