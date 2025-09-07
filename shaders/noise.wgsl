
// MIT License. © Stefan Gustavson, Munrocket
//
fn permute4(x: Vec4) -> Vec4 { return ((x * 34. + 1.) * x) % Vec4(289.); }
fn fade2(t: Vec2) -> Vec2 { return t * t * t * (t * (t * 6. - 15.) + 10.); }

fn perlinNoise2(P: Vec2) -> f32 {
    var Pi: Vec4 = floor(P.xyxy) + Vec4(0., 0., 1., 1.);
    let Pf = fract(P.xyxy) - Vec4(0., 0., 1., 1.);
    Pi = Pi % Vec4(289.); // To avoid truncation effects in permutation
    let ix = Pi.xzxz;
    let iy = Pi.yyww;
    let fx = Pf.xzxz;
    let fy = Pf.yyww;
    let i = permute4(permute4(ix) + iy);
    var gx: Vec4 = 2. * fract(i * 0.0243902439) - 1.; // 1/41 = 0.024...
    let gy = abs(gx) - 0.5;
    let tx = floor(gx + 0.5);
    gx = gx - tx;
    var g00: Vec2 = Vec2(gx.x, gy.x);
    var g10: Vec2 = Vec2(gx.y, gy.y);
    var g01: Vec2 = Vec2(gx.z, gy.z);
    var g11: Vec2 = Vec2(gx.w, gy.w);
    let norm = 1.79284291400159 - 0.85373472095314 *
        Vec4(dot(g00, g00), dot(g01, g01), dot(g10, g10), dot(g11, g11));
    g00 = g00 * norm.x;
    g01 = g01 * norm.y;
    g10 = g10 * norm.z;
    g11 = g11 * norm.w;
    let n00 = dot(g00, Vec2(fx.x, fy.x));
    let n10 = dot(g10, Vec2(fx.y, fy.y));
    let n01 = dot(g01, Vec2(fx.z, fy.z));
    let n11 = dot(g11, Vec2(fx.w, fy.w));
    let fade_xy = fade2(Pf.xy);
    let n_x = mix(Vec2(n00, n01), Vec2(n10, n11), Vec2(fade_xy.x));
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

fn hash2(p: Vec2) -> f32 {
    var p3 = fract(Vec3(p.x, p.y, p.x) * 0.13);
    p3 += dot(p3, p3.yzx + Vec3(3.333));
    return fract((p3.x + p3.y) * p3.z);
}

fn noise1(x: f32) -> f32 {
    let i = floor(x);
    let f = fract(x);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(hash1(i), hash1(i + 1.0), u);
}

fn noise2(x: Vec2) -> f32 {
    let i = floor(x);
    let f = fract(x);

    // Four corners in 2D of a tile
    let a = hash2(i);
    let b = hash2(i + Vec2(1.0, 0.0));
    let c = hash2(i + Vec2(0.0, 1.0));
    let d = hash2(i + Vec2(1.0, 1.0));

    let u = f * f * (3.0 - 2.0 * f);
    return mix(a, b, u.x) + (c - a) * u.y * (1.0 - u.x) + (d - b) * u.x * u.y;
}

fn noise3(x: Vec3) -> f32 {
    let step = Vec3(110.0, 241.0, 171.0);
    let i = floor(x);
    let f = fract(x);

    let n = dot(i, step);
    let u = f * f * (3.0 - 2.0 * f);

    return mix(
        mix(
            mix(
                hash1(n + dot(step, Vec3(0.0, 0.0, 0.0))),
                hash1(n + dot(step, Vec3(1.0, 0.0, 0.0))),
                u.x
            ),
            mix(
                hash1(n + dot(step, Vec3(0.0, 1.0, 0.0))),
                hash1(n + dot(step, Vec3(1.0, 1.0, 0.0))),
                u.x
            ),
            u.y
        ),
        mix(
            mix(
                hash1(n + dot(step, Vec3(0.0, 0.0, 1.0))),
                hash1(n + dot(step, Vec3(1.0, 0.0, 1.0))),
                u.x
            ),
            mix(
                hash1(n + dot(step, Vec3(0.0, 1.0, 1.0))),
                hash1(n + dot(step, Vec3(1.0, 1.0, 1.0))),
                u.x
            ),
            u.y
        ),
        u.z
    );
}