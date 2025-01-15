
// MIT License. © Stefan Gustavson, Munrocket
//
fn permute4(x: vec4f) -> vec4f { return ((x * 34. + 1.) * x) % vec4f(289.); }
fn fade2(t: vec2f) -> vec2f { return t * t * t * (t * (t * 6. - 15.) + 10.); }

fn perlinNoise2(P: vec2f) -> f32 {
    var Pi: vec4f = floor(P.xyxy) + vec4f(0., 0., 1., 1.);
    let Pf = fract(P.xyxy) - vec4f(0., 0., 1., 1.);
    Pi = Pi % vec4f(289.); // To avoid truncation effects in permutation
    let ix = Pi.xzxz;
    let iy = Pi.yyww;
    let fx = Pf.xzxz;
    let fy = Pf.yyww;
    let i = permute4(permute4(ix) + iy);
    var gx: vec4f = 2. * fract(i * 0.0243902439) - 1.; // 1/41 = 0.024...
    let gy = abs(gx) - 0.5;
    let tx = floor(gx + 0.5);
    gx = gx - tx;
    var g00: vec2f = vec2f(gx.x, gy.x);
    var g10: vec2f = vec2f(gx.y, gy.y);
    var g01: vec2f = vec2f(gx.z, gy.z);
    var g11: vec2f = vec2f(gx.w, gy.w);
    let norm = 1.79284291400159 - 0.85373472095314 *
        vec4f(dot(g00, g00), dot(g01, g01), dot(g10, g10), dot(g11, g11));
    g00 = g00 * norm.x;
    g01 = g01 * norm.y;
    g10 = g10 * norm.z;
    g11 = g11 * norm.w;
    let n00 = dot(g00, vec2f(fx.x, fy.x));
    let n10 = dot(g10, vec2f(fx.y, fy.y));
    let n01 = dot(g01, vec2f(fx.z, fy.z));
    let n11 = dot(g11, vec2f(fx.w, fy.w));
    let fade_xy = fade2(Pf.xy);
    let n_x = mix(vec2f(n00, n01), vec2f(n10, n11), vec2f(fade_xy.x));
    let n_xy = mix(n_x.x, n_x.y, fade_xy.y);
    return 2.3 * n_xy;
}



// credit: Morgan McGuire, https://www.shadertoy.com/view/4dS3Wd

fn hash1(p: f32) -> f32 {
    var p_mut = fract(p * 0.011);
    p_mut *= p_mut + 7.5;
    p_mut *= p_mut + p_mut;
    return fract(p_mut);
}

fn hash2(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.x, p.y, p.x) * 0.13);
    p3 += dot(p3, p3.yzx + vec3<f32>(3.333));
    return fract((p3.x + p3.y) * p3.z);
}

fn noise1(x: f32) -> f32 {
    let i = floor(x);
    let f = fract(x);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(hash1(i), hash1(i + 1.0), u);
}

fn noise2(x: vec2<f32>) -> f32 {
    let i = floor(x);
    let f = fract(x);

    // Four corners in 2D of a tile
    let a = hash2(i);
    let b = hash2(i + vec2<f32>(1.0, 0.0));
    let c = hash2(i + vec2<f32>(0.0, 1.0));
    let d = hash2(i + vec2<f32>(1.0, 1.0));

    let u = f * f * (3.0 - 2.0 * f);
    return mix(a, b, u.x) + (c - a) * u.y * (1.0 - u.x) + (d - b) * u.x * u.y;
}

fn noise3(x: vec3<f32>) -> f32 {
    let step = vec3<f32>(110.0, 241.0, 171.0);
    let i = floor(x);
    let f = fract(x);

    let n = dot(i, step);
    let u = f * f * (3.0 - 2.0 * f);

    return mix(
        mix(
            mix(
                hash1(n + dot(step, vec3<f32>(0.0, 0.0, 0.0))),
                hash1(n + dot(step, vec3<f32>(1.0, 0.0, 0.0))),
                u.x
            ),
            mix(
                hash1(n + dot(step, vec3<f32>(0.0, 1.0, 0.0))),
                hash1(n + dot(step, vec3<f32>(1.0, 1.0, 0.0))),
                u.x
            ),
            u.y
        ),
        mix(
            mix(
                hash1(n + dot(step, vec3<f32>(0.0, 0.0, 1.0))),
                hash1(n + dot(step, vec3<f32>(1.0, 0.0, 1.0))),
                u.x
            ),
            mix(
                hash1(n + dot(step, vec3<f32>(0.0, 1.0, 1.0))),
                hash1(n + dot(step, vec3<f32>(1.0, 1.0, 1.0))),
                u.x
            ),
            u.y
        ),
        u.z
    );
}