export default (appUrl, appEffects, deps, facts) => {

    var {Mustache, moment} = deps;

    const state = {}

    function elapsed(t1, t2) {
        return t2.getTime() - t1.getTime();
    }

    function hasProp(obj, prop) {
        return Object.prototype.hasOwnProperty.call(obj, prop);
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

    function isNoMatch(err) {
        return err && err.reason == "no_match";
    }

    function fmt(pattern, args) {
        return Mustache.render(pattern, args)
    }

    function flatten(arr) {
        return [].concat(...arr)
    }

    function getIn(paths, ctx){
        var value = ctx;
        for (var i = 0; i < paths.length; i++) {
            var path = paths[i];
            if (!hasProp(value, path)) {
                if (path === "$" && typeOf(value) === "object") {
                    return {value: Object.values(value)}
                }

                return error(path, value, "Missing key");

            }
            value = value[path];
        }
        return {value};
    }
    
    function getInOrDefault(spec, defaultVal, ctx) {
        var {err, value} = getIn(spec, ctx);
        if (err) return encode(defaultVal, ctx);
        return {value};
    }

    function encodeObject(spec, ctx) {
        var out = {};
        for (var k in spec.object) {
            if (hasProp(spec.object, k)) {
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
        return getIn(spec.key.substring(1).split("."), ctx);
    }

    function encodeKeyOrDefault(spec, defaultVal, ctx) {
        var {err, value} = encodeKey(spec, ctx);
        if (err) return encode(defaultVal, ctx);
        return {value};
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
        var { pattern, date } = spec.formatDate;
        var { err, value } = encode(pattern, ctx);
        if (err) return error(spec, ctx, err);
        pattern = value;
        var { err: dateErr, value: dateValue } = encode(date, ctx);
        if (dateErr) return error(spec, ctx, dateErr);
        switch (pattern) {
            case "relative":
                return { value: moment(dateValue).fromNow() };
            default:
                return { value: moment(dateValue).format(pattern) };
        }
    }

    function encodeMaybe(spec, ctx) {
        const { err, value } = encode(spec.maybe, ctx);
        if (!err || !spec.otherwise) return {value};
        return encode(spec.otherwise, ctx);
    }

    function encodeMaybeWith(spec, ctx) {
        var obj = {}
        for (var i=0; i<spec.maybe_with.length; i++) {
            var prop = spec.maybe_with[i];
            var {value} = encode("@"+prop, ctx);
            if (value && value.length) {
                obj[prop] = value
            }
       }

        return {value: obj};
    }

    function encodeEqual(spec, ctx) {
        if (!spec.equal.length) return { value: false };
        var { err, value } = encode(spec.equal[0], ctx);
        if (err) return error(spec, ctx, err);
        var expected = value;
        for (var i = 1; i < spec.equal.length; i++) {
            var s = spec.equal[i];
            var { err: equalErr, value: equalValue } = encode(s, ctx);
            if (equalErr) return error(spec, ctx, equalErr);
            if (equalValue!= expected) return { value: false };
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
        return {value: !isEmpty(value)};
    }

    function encodeNot(spec, ctx) {
        var { err, value } = encode(spec.not, ctx);
        if (err) return error(spec, ctx, err);
        if (typeof (value) != 'boolean') return error(spec, ctx, {
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

            var { err: whenErr, value: whenValue } = encode(s.when, ctx);
            if (whenErr) return error(s.when, ctx, whenErr);
            if (whenValue) {
                s = s.then || s;
                var { err: thenErr, value: thenValue} = encode(s, ctx);
                if (thenErr) return error(s, ctx, thenErr);
                return { value: thenValue };
            }
        }
        return error(spec, ctx, "No clause matched");
    }

    function encodeUsingEncoder(spec, ctx) {
        var { err, value } = encode(spec.encoder, ctx);
        if (err) return error(spec, ctx, err);
        var encName = value;
        var enc = state.app.encoders[encName];
        if (!enc) return error(spec, ctx, "No such encoder: " + encName);
        var encoderCtx = ctx;
        if (spec.params) {
            var { err: paramsErr, value: paramsValue } = encode(spec.params, ctx);
            if (paramsErr) return error(spec.params, ctx, paramsErr);
            encoderCtx = Object.assign({}, ctx, paramsValue);
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
            formatDate: {
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
        var { err: denErr, value: denValue } = encode(spec.percent.den, ctx);
        if (denErr) return error(spec.percent.den, ctx, denErr);
        var den = denValue;
        if (!den) return { value: 0 };
        return { value: Math.floor(num / den) * 100 };
    }

    //function encodeAny(spec, ctx) {
    //    if (spec.any === 'object' && typeof(data) === 'object' && !Array.isArray(data)) {
    //        return {value: ctx};
    //    }

    //    return error(spec, data, "any spec not supported");
    //}

    function encodeData(spec) {
        return {value: spec.data};
    }

    function encodeEmpty(spec, ctx) {
        var {err, value} = encode(spec.empty, ctx);
        if (err) return error(spec.empty, ctx, err);
        return {value: isEmpty(value)};
    }

    function encodeHas(spec, ctx) {
        var {err, value} = encode(spec.has, ctx);
        if (err) return error(spec.has, ctx, err);
        return {value: hasProp(ctx, value)};
    }

    function encodeMember(spec, ctx) {
        var {err, value} = encode(spec.member, ctx);
        if (err) return error(spec.member, ctx, err);
        var valueType = typeOf(value);

        if (valueType != "list") return error(spec, ctx, {
            reason: "Type mismatch",
            data: value,
            expected: "list"
        });

        if (value.length != 2) return error(spec, ctx, {
            reason: "invalid lenght",
            data: value,
            expect: {length: 2}
        });

        var [col, item] = value;
        var colType = typeOf(col);

        if (colType != "list") return error(spec, ctx, {
            reason: "Type mismatch",
            data: col,
            expected: "list"
        });

        return {value: col.indexOf(item) != -1};
    }

    function encodeAdd(spec, ctx) {
        var {err: itemErr, value: item} = encode(spec.add, ctx);
        if (itemErr) return error(spec.add, ctx, itemErr);

        var {err: colErr, value: col} = encode(spec.to, ctx);
        if (colErr) return error(spec.to, ctx, colErr);

        var colType = typeOf(col);

        if (colType != "list") return error(spec, ctx, {
            reason: "Type mismatch",
            data: col,
            expected: "list"
        });

        return {value: col.concat([item])};
    }

    function encodeRemove(spec, ctx){
        var {err: itemErr, value: item} = encode(spec.remove, ctx);
        if (itemErr) return error(spec.remove, ctx, itemErr);

        var {err: colErr, value: col} = encode(spec.from, ctx);
        if (colErr) return error(spec.from, ctx, colErr);

        var colType = typeOf(col);

        if (colType != "list") return error(spec, ctx, {
            reason: "Type mismatch",
            data: col,
            expected: "list"
        });

        var out = col.filter((i) => {
            return i != item;
        });

        console.log("removing from list", {col, item, out});
        return {value: out};
    }

    function encodeMatch(spec, ctx) {
        var {err, value} = encode(spec.match, ctx);
        if (err) return error(spec.match, ctx, err);
        var {err: decodeErr } = decode(value, ctx);
        return {value: !decodeErr};
    }


    function encodeIndex(spec, ctx) {
        var path = isEmpty(spec.index) ? "@items" : spec.index;
        var {err, value} = encode(path, ctx);
        if (err) return error(path, ctx, err);
        var source = value;

        var sourceType = typeOf(source);
        if (sourceType != "list") return error(spec, ctx, {
            reason: "Type mismatch",
            data: source,
            actualType: sourceType,
            expectedType: "list"
        });

        var indexExpr = isEmpty(spec.with) ? "@item.id" : spec.with;

        var out = {}
        for( var i=0; i<source.length; i++) {

            var item = source[i];
            var itemCtx = Object.assign({}, ctx);
            itemCtx[spec.as || "item"] = item;

            var {err: indexErr, value: indexValue} = encode(indexExpr, itemCtx);
            if(indexErr) return error(indexExpr, itemCtx, indexErr);

            var key = indexValue;
            if( typeOf(key) != 'text') return error(indexExpr, itemCtx, {
                reason: "Type mismatch",
                actual: value,
                expectedType: "text"
            });
            out[key] = item;
        }
        return {value: out};

    }

    function encodeGroup(spec, ctx) {

        var path = isEmpty(spec.group) ? "@items" : spec.group;
        var {err, value} = encode(path, ctx);
        if (err) return error(path, ctx, err);
        var source = value;

        var sourceType = typeOf(source);
        if (sourceType != "list") return error(spec, ctx, {
            reason: "Type mismatch",
            data: source,
            actualType: sourceType,
            expected: "list"
        });

        var groupExpr = isEmpty(spec.with) ? "@item.id" : spec.with;

        var out = {}

        for( var i=0; i<source.length; i++) {

            var item = source[i];
            var itemCtx = Object.assign({}, ctx);
            itemCtx[spec.as || "item"] = item;

            var {err: groupErr, value: groupValue} = encode(groupExpr, itemCtx);
            if(groupErr) return error(groupExpr, itemCtx, groupErr);

            var key = groupValue;
            if( typeOf(key) != 'text') return error(groupExpr, itemCtx, {
                reason: "Type mismatch",
                actual: value,
                expected: "text"
            });

            if (!out[key]) out[key] = []
            out[key].push(item);
        }
        return {value: out}
    }

    function encodeResolve(spec, ctx) {
        var {err, value} = encode(spec.resolve, ctx);
        if (err) return error(spec.resolve, ctx, err);
        var path = value;
        var pathType = typeOf(path);
        switch (pathType) {
            case 'list':
                path = "@" + path.join(".");
                return encodeKeyOrDefault({key: path}, spec.otherwise, ctx);

            case 'text':
                return getInOrDefault([path], spec.otherwise, ctx);

            default:
                return error(spec, ctx, {
                    reason: "Type mismatch",
                    data: path,
                    expectedType: ['list', 'text'],
                    actualType: pathType
                });
        }
    }

    function encodeLet(spec, ctx) {
        var {err, value} = encode(spec.let, ctx);
        if (err) return error(spec.let, ctx, err);
        var letCtx = Object.assign({}, ctx, value);
        return encode(spec.in, letCtx);
    }




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

    function encodeConcat(spec, ctx) {
        var lists = [];
        for (var i = 0; i < spec.concat.length; i++) {
            var { err, value } = encode(spec.concat[i], ctx);
            if (err) return error(spec, ctx, err);
            lists[i] = value;
        }
        return { value: flatten(lists) }
    }

    function encodeMerge(spec, ctx) {
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
        if (!value || value.length < 2) return error(spec, ctx, {
            error: "not_enough_arguments",
            actual: value,
            expect: {type: "list", min_length: 2}
        });
        var num = value[0];
        for (var i = 1; i < value.length; i++) {
            if (typeof (value[i]) != 'number') return error(spec, value, "not_a_number");
            if (!value[i]) return error(spec, value, "division_by_zero");
            num = num / value[i];
        }
        if (!hasProp(spec, "decimals")) return { value: num };
        return { value: num.toFixed(spec.decimals) };
    }

    var sizeEncoders = {
        "undefined": () => { return 0 },
        "list": (d) => { return d.length },
        "object": (d) => { return Object.keys(d).length },
        "string": (d) => { return d.length },
        "number": (d) => { return d.number },
        "boolean": () => { return 0 }
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
        for (var i = 0; i < spec.oneOf.length; i++) {
            var { err, value } = encode(spec.oneOf[i], ctx);
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
            var { err: encoderErr, value: encoderValue } = encode(spec.encoder, ctx);
            if (encoderErr) return error(spec.encoder, ctx, encoderErr);
            cmd.encoder = encoderValue;
        }
        return { value: cmd };
    }

    function encodeSplit(spec, ctx) {
        var { err, value } = encode(spec.using, ctx);
        if (err) return error(spec, ctx, err);
        var sep = value;
        var { err: splitErr, value: splitValue } = encode(spec.split, ctx);
        if (splitErr) return error(spec.split, ctx, splitErr);
        switch (typeof (splitValue)) {
            case "string":
                return { value: splitValue.split(sep) };
            default:
                return error(spec, splitValue, "not_a_string");
        }
    }

    function encodeJoin(spec, ctx) {
        var { err, value } = encode(spec.using, ctx);
        if (err) return error(spec, ctx, err);
        var sep = value;
        var { err: joinErr, value: joinValue } = encode(spec.join, ctx);
        if (joinErr) return error(spec, ctx, joinErr);
        if (!Array.isArray(joinValue)) return error(spec.join, joinValue, "not_a_list");
        return { value: joinValue.join(sep) };
    }

    function encodeFirst(spec, ctx) {
        var {err, value: first } = encode(spec.first, ctx);
        if (err) return error(spec.first, ctx, err);
        var {err, value: items } = encode(spec.in, ctx);
        if (err) return error(spec.in, ctx, err);
        if (!Array.isArray(items)) return error(spec, items, "not_a_list");
        if (!items.length) return error(spec, ctx, "empty_list");
        for (var i=0; i<items.length; i++) {
            var item = items[i];
            var {err, decoded} = decode(first, item);
            if (!err && decoded) {
                return {value: item};
            } 
        }
        return error(spec, ctx, "no_item_matched"); 
    }

    function encodeHead(spec, ctx) {
        var { err, value } = encode(spec.head, ctx);
        if (err) return error(spec, ctx, err);
        if (!Array.isArray(value)) return error(spec, value, "not_a_list");
        const [head] = value;
        if (!head) return error(spec, value, "empty_list");
        return { value: head };

    }

    function encodeTail(spec, ctx) {
        var { err, value } = encode(spec.tail, ctx);
        if (err) return error(spec, ctx, err);
        if (!Array.isArray(value)) return error(spec, value, "not_a_list");
        const [, ...tail] = value;
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
        var inSpec = spec['in'];
        var { err: inErr, value: inValue } = encode(inSpec, ctx);
        if (inErr) return error(inSpec, ctx, inErr);
        return { value: inValue.charAt(c) };
    }

    function encodeGreaterThan(spec, ctx) {
        if (spec.greaterThan.length < 2) return error(spec, ctx, "not_enough_arguments");
        var { err, value: v1 } = encode(spec.greaterThan[0], ctx);
        if (err) return error(spec, ctx, err);
        var { err: err2, value: v2 } = encode(spec.greaterThan[1], ctx);
        if (err2) return error(spec, ctx, err2);
        return { value: v1 > v2};
    }

    function encodeLowerThan(spec, ctx) {
        if (spec.lower_than.length < 2) return error(spec, ctx, "not_enough_arguments");
        var { err, value: v1 } = encode(spec.lower_than[0], ctx);
        if (err) return error(spec, ctx, err);
        var { err: err2, value: v2 } = encode(spec.lower_than[1], ctx);
        if (err2) return error(spec, ctx, err2);
        return { value: v1 < v2 };
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
            if (!hasProp(spec, "default")) return error(spec, ctx, {
                error: "no_clause"
            });

            clause = spec["default"]

        }
        var { err: clauseErr, value: clauseValue} = encode(clause, ctx);
        if (clauseErr) return error(clause, ctx, clauseErr);
        return { value: clauseValue };
    }

    function encodeChoose(spec, ctx) {
        var {err, value : v1} = encode(spec.choose, ctx);
        if (err) return error(spec.choose, ctx, err);
        var {err, value: when} = encode(spec.when, ctx);
        if (err) return error(spec.when, ctx, err);
        if (when === v1) {
            return encode(spec.then, ctx);
        } else {
            return encode(spec.otherwise, ctx);
        }
    }

    function encodePipeline(spec, ctx) {
        var specs = spec.pipeline;
        if (!Array.isArray(specs)) return error(spec, ctx, "not a list of specs");
        var pCtx = Object.assign({}, ctx);
        var as = spec.as || "items";
        for (var i = 0; i < specs.length; i++) {
            var pSpec = specs[i];
            var { err, value } = encode(pSpec, pCtx);
            if (err) return error(pSpec, value, err);
            pCtx[as] = value;

        }
        return { value: pCtx[as] };
    }

    function encodeFilter(spec, ctx) {
        var itemsSpec = isEmpty(spec.filter) ? "@items" : spec.filter;
        var { err, value } = encode(itemsSpec, ctx);
        if (err) return error(itemsSpec, ctx, err);
        if (!Array.isArray(value)) return error(spec.filter, value, "Not a list");
        var items = value;

        var out = [];
        for (var i = 0; i < items.length; i++) {
            var { err: withErr, decoded } = decode(spec.with, items[i], ctx);
            if (!withErr && decoded) {
                out.push(items[i]);
            }
        }
        return { value: out };
    }

    function encodeReject(spec, ctx) {
        var itemsSpec = isEmpty(spec.filter) ? "@items" : spec.filter;
        var { err, value } = encode(itemsSpec, ctx);
        if (err) return error(itemsSpec, ctx, err);
        if (!Array.isArray(value)) return error(spec.filter, value, "Not a list");
        var items = value;

        var out = [];
        for (var i = 0; i < items.length; i++) {
            var item = items[i];
            var itemCtx = Object.assign({}, ctx);
            itemCtx[spec.as || "item"] = item;
            var { err: withErr, decoded } = decode(spec.with, item, itemCtx);
            if (withErr && !decoded) {
                out.push(items[i]);
            }
        }
        return { value: out };
    }

    function encodeMap(spec, ctx) {
        var itemsSpec = isEmpty(spec.map) ? "@items" : spec.map;
        var { err, value } = encode(itemsSpec, ctx);
        if (err) return error(itemsSpec, ctx, err);
        if (!Array.isArray(value)) return error(spec.map, value, "Not a list");
        var items = value;

        var out = [];
        for (var i = 0; i < items.length; i++) {
            var itemCtx = Object.assign({}, ctx);
            itemCtx[spec.as || 'item'] = items[i];
            var { err: withErr, value: withValue } = encode(spec.with, itemCtx);
            if (withErr) return error(spec.with, ctx, withErr);
            out.push(withValue);
        }

        if (spec.flatten == true) {
            out = out.flat();
        }
        return { value: out };
    }

    function encodeCombine(spec, ctx) {
        var path = isEmpty(spec.combine) ? "@items" : spec.combine;

        var {err, value: source} = encode(path, ctx);
        if (err) return error(path, ctx, err);

        var {err: withErr, value: dest} = encode(spec.with, ctx);
        if (withErr) return error(spec.with, ctx, withErr);

        var sourceType = typeOf(source);
        var destType = typeOf(dest);

        if (sourceType != destType) return error(spec, ctx, {
            reason: "Type mismatch",
            data: dest,
            actualType: dest,
            expectedType: sourceType
        });

        switch(sourceType) {
            case "object" :
                return {value: Object.assign(source, dest)}
            case "list" :
                return {value: source.concat(dest)};
            default:
                return {value: source + dest}
        }
    }

    function encodeFlatmap(spec, ctx) {
        return encodeMap(Object.assign({}, spec, {
            map: spec.flat_map,
            flatten: true
        }), ctx);
    }

    function encodeUnique(spec, ctx) {
        var itemsSpec = isEmpty(spec.unique) ? "@items" : spec.unique;
        var { err: itemsErr, value: items } = encode(itemsSpec, ctx);
        if (itemsErr) return error(itemsSpec, ctx, itemsErr);
        if (!Array.isArray(items)) return error(itemsSpec, items, {
            error: "type_mistmatch",
            actual: items,
            expected: "list"
        });

        var index = {};
        var bySpec = spec.by || "@item";

        for (var i = 0; i < items.length; i++) {

            var item = items[i];
            if (item) {
                var itemCtx = Object.assign({}, ctx);
                itemCtx[spec.as || "item"] = item;

                var { err: byErr, value: byValue} = encode(bySpec, itemCtx);
                if (byErr) return error(bySpec, itemCtx, byErr);
                if (!byValue || typeof (byValue) != 'string') return error(byValue, bySpec, {
                    error: "type_mistmatch",
                    actual: byValue,
                    expected: "string"
                });
                index[byValue] = item;
            }
        }

        return { value: Object.values(index) };
    }

    function encodeTake(spec, ctx) {
        var {err, value} = encode(spec.take, ctx);
        if (err) return error(spec.take, ctx, err);
        if (!typeOf(value) === "list") return error(spec.take, ctx, {
            error: "type_mistmatch",
            actual: value,
            expected: "list"
        });

        var keys = value;

        var {err: fromErr, value: fromValue} = encode(spec.from, ctx);
        if (fromErr) return error(spec.from, ctx, fromErr);
        if (!typeOf(fromValue) === "object") return error(spec.from, ctx, {
            error: "type_mistmatch",
            actual: fromValue,
            expected: "object"
        });

        var source = fromValue;

        var out = {}
        for (var i=0; i<keys.length; i++) {
            var key = keys[i];
            out[key] = source[key];
        }

        return {value: out};
    }

    function uuidv4() {
        return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, function(c) {
            var r = Math.random() * 16 | 0, v = c == 'x' ? r : (r & 0x3 | 0x8);
            return v.toString(16);
        });
    }

    function encodeUuid(_spec, _ctx) {
        return {value: uuidv4()};
    }

    function encodeCamel(spec, ctx) {
        var {err, value} = encode(spec.camel, ctx);
        if (err) return error(spec, err, ctx);
        return { value: value.toLowerCase().replace(/[^a-zA-Z0-9]+(.)/g, (m, chr) => chr.toUpperCase()) }
    }

    function encode(spec, ctx) {
        if (spec == undefined || spec == null) return error(spec, ctx, "Missing encoding spec");
        switch (typeof (spec)) {
            case "object":
                if (hasProp(spec, "text")) return encodeText(spec, ctx);
                if (hasProp(spec, "char")) return encodeChar(spec, ctx);
                if (Array.isArray(spec)) return encodeList(spec, ctx);
                if (spec.object) return encodeObject(spec, ctx);
                if (hasProp(spec, "switch")) return encodeSwitch(spec, ctx);
                if (spec.choose) return encodeChoose(spec, ctx);
                if (spec.format) return encodeFormat(spec, ctx);
                if (spec.formatDate) return encodeFormatDate(spec, ctx);
                if (spec.timestamp) return encodeTimestamp(spec, ctx);
                if (spec.maybe) return encodeMaybe(spec, ctx);
                if (spec.maybe_with) return encodeMaybeWith(spec, ctx);
                if (spec.equal) return encodeEqual(spec, ctx);
                if (spec.either) return encodeEither(spec, ctx);
                if (spec.oneOf) return encodeOneOf(spec, ctx);
                if (spec.effect) return encodeCmd(spec, ctx);
                if (spec.encoder) return encodeUsingEncoder(spec, ctx);
                if (spec.is_set) return encodeIsSet(spec, ctx);
                if (spec.not) return encodeNot(spec, ctx);
                if (spec.and) return encodeAnd(spec, ctx);
                if (spec.or) return encodeOr(spec, ctx);
                if (spec.first) return encodeFirst(spec, ctx);
                if (spec.head) return encodeHead(spec, ctx);
                if (spec.tail) return encodeTail(spec, ctx);
                if (spec.last) return encodeLast(spec, ctx);
                if (spec.split) return encodeSplit(spec, ctx);
                if (spec.join) return encodeJoin(spec, ctx);
                if (spec.concat) return encodeConcat(spec, ctx);
                if (spec.merge) return encodeMerge(spec, ctx);
                if (spec.prettify) return encodePrettify(spec, ctx);
                if (spec.percent) return encodePercent(spec, ctx);
                if (spec.divide) return encodeDivide(spec, ctx);
                if (spec.sum) return encodeSum(spec, ctx);
                if (spec.size_of) return encodeSizeOf(spec, ctx);
                if (spec.lowercase) return encodeLowerCase(spec, ctx);
                if (spec.uppercase) return encodeUpperCase(spec, ctx);
                if (spec.capitalize) return encodeCapitalize(spec, ctx);
                if (spec.greaterThan) return encodeGreaterThan(spec, ctx);
                if (spec.lower_than) return encodeLowerThan(spec, ctx);
                if (spec.regex) return encodeRegex(spec, ctx);
                if (spec.pipeline) return encodePipeline(spec, ctx);
                if (spec.map) return encodeMap(spec, ctx);
                if (spec.flat_map) return encodeFlatmap(spec, ctx);
                if (spec.filter) return encodeFilter(spec, ctx);
                if (spec.reject) return encodeReject(spec, ctx);
                if (spec.unique) return encodeUnique(spec, ctx);
                if (spec.data) return encodeData(spec, ctx);
                if (spec.has) return encodeHas(spec, ctx);
                if (spec.member) return encodeMember(spec, ctx);
                if (spec.empty) return encodeEmpty(spec, ctx);
                if (spec.add) return encodeAdd(spec, ctx);
                if (spec.remove) return encodeRemove(spec, ctx);
                if (spec.match) return encodeMatch(spec, ctx);
                if (spec.combine) return encodeCombine(spec, ctx);
                if (spec.index) return encodeIndex(spec, ctx);
                if (spec.group) return encodeGroup(spec, ctx);
                if (spec.resolve) return encodeResolve(spec, ctx);
                if (spec.let) return encodeLet(spec, ctx);
                if (spec.take) return encodeTake(spec, ctx);
                if (spec.uuid) return encodeUuid(spec, ctx);
                if (spec.camel) return encodeCamel(spec, ctx);
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
            if (hasProp(data, k)) {
                var keySpec = spec.object[k];
                var { err, decoded } = decode(keySpec, data[k], ctx);
                if (err) return error(keySpec, data[k], err);
                out[k] = decoded;
            } else {
                return error(spec, data, "no_match");
            }
        }
        return { decoded: out };
    }
    
    function decodeEntryWith(spec, data, ctx) {
        var {err, value} = encode(spec.entry_with, ctx);
        if (err) return error(spec.entry_with, ctx, err);
        switch(typeOf(data)) {
            case "object":
                for (var k in data) {
                    if (hasProp(data, k)) {
                        var v = data[k];
                        if (v == value) {
                            return {decoded: data};
                        }
                    }
                }

            default: {}
        }
        return error(spec, data, "no_match");
    }

    function decodeOtherThan(spec, data, ctx) {
        var { err, value } = encode(spec.otherThan, ctx);
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

    function decodeAny(spec, data) {
        if (data == undefined || data == null) return error(spec, data, "no_data");
        var d = anyConditions[spec.any];
        if (!d) return error(spec, data, "unknown_any_condition");
        return d(spec, data);
    }

    function decodeList(spec, data, ctx) {
        if (!Array.isArray(data)) return error(spec, data, "no_match");
        var out = [];
        var itemSpec;
        var i;
        var item;
        if (Array.isArray(spec.list)) {
            for (i = 0; i < spec.list.length; i++) {
                item = data[i];
                itemSpec = spec.list[i];
                var { err, decoded } = decode(itemSpec, item, ctx);
                if (err) return error(spec, data, err);
                out.push(decoded);
            }
            return { decoded: out };
        } else {
            itemSpec = spec.list;
            for (i = 0; i < data.length; i++) {
                item = data[i];
                var { err: itemErr, decoded: decodedItem } = decode(itemSpec, item, ctx);
                if (itemErr) return error(spec, data, itemErr);
                out.push(decodedItem);
            }
            return { decoded: out };
        }
    }

    function decodeWith(spec, data, ctx) {
        if (!data) return error(spec, data, "no_data");
        var dataType = typeOf(data);
        switch (dataType) {
            case "list":
                for (var i=0; i<data.length; i++) {
                    var item = data[i];
                    var {err, decoded} = decode(spec.with, item, ctx);
                    if (!err && decoded) return {decoded: data}
                }

                return error(spec, data, "no_match");

            case "object":
                return decodeObject({object: spec.with}, data, ctx);

            default:
                return error(spec, data, {error: "type_mistmatch", actual: dataType, expected: ["list", "object"]});
        }
    }

    function decodeWithout(spec, data, ctx) {
        if (!data) return error(spec, data, "no_data");
        var dataType = typeOf(data);
        switch (dataType) {
            case "object":
                var {err, value} = encode(spec.without, ctx)
                if (err) return error(spec, ctx, err)
                if (typeOf(value) != "list") return error(spec.without, ctx, {error: "type_mismatch", actual: value, expected: "list"});

                for (var i=0; i<value.length; i++) {
                    var key = value[i];
                    if (hasProp(data, key)) {
                        return error(spec, data, {error: "unexpected_key", key: key, data: data});
                    }
                }
                return {decoded: data}

            default:
                return error(spec, data, {error: "type_mistmatch", actual: dataType, expected: ["object"]});
        }
    }


    function intersection(a, b) {
        const s = new Set(b);
        return a.filter(x => s.has(x));
    }

    function decodeAll(spec, data, ctx) {
        if (!data) return error(spec, data, "no_data");
        var dataType = typeOf(data);

        if (dataType != 'list') return error(spec, data, {
            error: "type_mistmatch",
            actual: data,
            expected: "list"
        });

        var {err, value: items} = encode(spec.all, ctx);
        if (err) return error(spec.all, ctx, err);

        var itemsType = typeOf(items);
        if (itemsType!= 'list') return error(spec, data, {
            error: "type_mistmatch",
            actual: itemsType,
            expected: "list"
        });

        var inter = intersection(items, data);
        return inter.length == items.length ? {decoded: data} : error(spec, data, "no_match");
    }

    function decodeSome(spec, data, ctx) {
        if (!data) return error(spec, data, "no_data");
        var dataType = typeOf(data);

        if (dataType != 'list') return error(spec, data, {
            error: "type_mistmatch",
            actual: data,
            expected: "list"
        });

        var {err, value: items} = encode(spec.some, ctx);
        if (err) return error(spec.some, ctx, err);

        var itemsType = typeOf(items);
        if (itemsType!= 'list') return error(spec, data, {
            error: "type_mistmatch",
            actual: itemsType,
            expected: "list"
        });

        var inter = intersection(items, data);
        return inter.length ? {decoded: data} : error(spec, data, "no_match");
    }

    function decodeEmpty(spec, data) {
        if (!data || isEmpty(data)) return {decoded: data};
        return error(spec, data, "no_match")
    }

    function decodeNonEmpty(spec, data) {
        var {err} = decodeEmpty({empty: spec.non_empty}, data);
        if (isNoMatch(err)) return {decoded: data};
        return error(spec, data, "no_match");
         
    }

    function decodeOne(spec, data, ctx) {
        function _(i) {
            if (i == spec.oneOf.length) return error(spec, data, "no_match")
            var s = spec.oneOf[i];
            var { err, decoded } = decode(s, data, ctx);
            if (err) return _(i + 1);
            return { decoded };
        }
        return _(0);
    }


    function decodeJson(spec) {
        try {
            return { value: JSON.parse(spec.json) };
        } catch (e) {
            return { err: { json: spec.json, error: e } };
        }
    }

    function decodeSize(spec, data) {
        var { err, value } = encode(spec.size, data);
        if (err) return error(spec, data, err);
        var dataType = typeOf(data);

        switch (dataType) {
            case 'object':
                return (Object.keys(data).length == value) ? { decoded: data } :
                    error(spec, data, "no_match");
            case 'list':
                return data.length == value ?  { decoded: data } :
                    error(spec, data, "no_match");

            case 'string':
                if (data && data.length == value) return { decoded: data };
        }

        return error(spec, data, "no_match");
    }

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
        if (typeof(data) != 'string') data = ""+data;
        return data.match(regex) ? { decoded: data } : error(spec, data, "no_match");
    }

    function decodeSame(spec, data) {
        return spec === data ? { deocded: data } : error(spec, data, "no_match");
    }

    function decode(spec, data, ctx) {
        switch (typeof (spec)) {
            case "object":
                if (Array.isArray(spec)) return decodeList({ list: spec }, data, ctx);
                if (hasProp(spec, "text")) return decode(spec.text, data, ctx);
                if (spec.key) return decodeKey(spec, data, ctx);
                if (spec.object) return decodeObject(spec, data, ctx);
                if (spec.any) return decodeAny(spec, data, ctx);
                if (spec.list) return decodeList(spec, data, ctx);
                if (spec.entry_with) return decodeEntryWith(spec, data, ctx);
                if (spec.with) return decodeWith(spec, data, ctx);
                if (spec.without) return decodeWithout(spec, data, ctx);
                if (spec.all) return decodeAll(spec, data, ctx);
                if (spec.some) return decodeSome(spec, data, ctx);
                if (spec.empty) return decodeEmpty(spec, data, ctx);
                if (spec.non_empty) return decodeNonEmpty(spec, data, ctx);
                if (spec.otherThan) return decodeOtherThan(spec, data, ctx);
                if (spec.oneOf) return decodeOne(spec, data, ctx);
                if (spec.json) return decodeJson(spec, data, ctx);
                if (spec.size) return decodeSize(spec, data, ctx);
                if (spec.like) return decodeLike(spec, data, ctx);
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
        console.log("cmds", spec);
        var cmds = [];
        switch (typeOf(spec)) {
            case "object":
                cmds = cmdsFromMap(spec, data);
                break;
                
            case "list":
                cmds = cmdsFromList(spec, data);
                break;

            default:
                console.error("cmds spec not supported", spec);
        }

        return {value: cmds};
    }

    function cmdsFromList(spec, data) {
        var cmds = [];
        for (var i=0; i<spec.length; i++) {
            var cmdSpec = spec[i];
            switch (typeOf(cmdSpec)) {
                case "object":
                    // we support objects with a single entry
                    // ie { effect => encoder }
                    var entries = Object.getOwnPropertyNames(cmdSpec);
                    var effect = entries[0];
                    var encSpec = cmdSpec[effect];
                    
                    var {err, value} = encode(encSpec, data, {});
                    if (err) {
                        console.error("error encoding cmd", {effect: effect, encoder: encSpec, err});
                        continue;
                    }
                    cmds.push({
                        effect: entries[0],
                        encoder: value
                    });

                    break;

                case "string": 
                    cmds.push({effect: cmdSpec});
                    break;
                    
                default: 
                    console.error("cmd spec not supported within a list", cmdSpec);
            }
            
        }

        return cmds;
    }

    function cmdsFromMap(spec, data) {
        var cmds = [];
        var effects = Object.getOwnPropertyNames(spec);
        for (var i = 0; i < effects.length; i++) {
            var eff = effects[i];
            var enc = spec[eff];
            if (isEmpty(enc)) {
                cmds.push({ effect: eff });
            } else {
                var { err, value } = encode(enc, data, {});
                if (err) {
                    console.error("error encoding cmd", {effect: eff, encoder: enc, err});
                }
                cmds.push({
                    effect: eff,
                    encoder: value
                });
            }
        }

        return cmds;
    }

    function isEmpty(obj) {
        if (!obj || (obj.length && obj.length == 0)) return true;
        for (var x in obj) { 
            if (hasProp(obj, x)) return false; 
        }
        return true;
    }

    function withSettings(m) {
        return Object.assign({}, state.app.settings, m);
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
                    console.error("No such encoder", {cmd, encoders});
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
            if (err) return error(c.condition, ctx, err);
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
        const { encoders, decoders, update } = state.app;
        var effectDecoders = decoders[effect];
        log("[core] decoding", {effect, data: ev, decoders: effectDecoders});
        var { err, decoded } = tryDecoders(ev, effectDecoders);
        if (err) {
            console.error("Decode error", {effect: effect, data: ev, decoders: effectDecoders, reason: err});
            return;
        }
        const { msg, data } = decoded;
        log("[core] decoded", decoded);
        const t1 = new Date();
        var ctx = {
            model: state.model,
            data: data
        };
        var { err: selectUpdateErr, spec } = selectUpdate(msg, update, ctx);
        if (selectUpdateErr) {
            console.error("Select update Uerror", selectUpdateErr);
            return;
        }
        var { err: whereErr, value } = withWhere(spec, ctx);
        if (whereErr) {
            console.error("Where error", whereErr);
            return;
        }
        ctx = value;
        log("[core] update spec", { spec, ctx });
        
        var newModel = state.model;
        if (spec.model) {
            var {err, value} = encode(spec.model, ctx);
            if (err) {
                console.error("Encode new model error", { spec: spec.model, ctx: ctx, error: err}); 
                return err
            }
            newModel = Object.assign(newModel, value);
        }

        var cmds = null;
        if (spec.cmds) {
            var {err, value} = encode(spec.cmds, newModel);
            if (err) {
                console.error("Encode commands error", { spec: spec.model, ctx: ctx, error: err}); 
                return err
            }
            cmds = value;
        }

        // we succesfully encoded the new model 
        // and commands. We can transition to the next model
        // and start applying commands
        state.model = newModel;
        log("[core] new model", state.model);

        const t2 = new Date();
        if (spec.cmds) applyCmds(encoders, state.effects, cmds, state.model);
        const t3 = new Date();


        //var { err: updateErr, value: updateValue } = encode(spec, ctx);
        //if (updateErr) {
        //    console.error("Encode new model error", updateErr);
        //    return err;
        //}
        //var { model, cmds } = updateValue;
        //Object.assign(state.model, model);
        //log("[core] new model", state.model);
        //const t2 = new Date();
        //if (spec.cmds) applyCmds(encoders, state.effects, cmds, state.model);
        //const t3 = new Date();
        

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
        var { model, cmds } = init;
        model = Object.assign({}, facts, model);
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

    function indexedDecoders(effects) {
        var index = {};
        for (var k in effects) {
            if (hasProp(effects, k)) {
                var decs = effects[k];
                for (var dec in decs) {
                    if (hasProp(decs, dec)) {
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
            if (hasProp(mods, n)) {
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
    }

    app(appUrl, function (app) {
        state.app = compiledApp(app);
        log("app", app);
        effects(appEffects, (effs) => {
            state.effects = effs;
            init(app);
        });
    });
}

