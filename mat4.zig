pub fn identity(comptime T: type) [4][4]T {
    return .{
        .{ 1, 0, 0, 0 },
        .{ 0, 1, 0, 0 },
        .{ 0, 0, 1, 0 },
        .{ 0, 0, 0, 1 },
    };
}

pub fn mul(comptime T: type, a: [4][4]T, b: [4][4]T) [4][4]T {
    return mat.mul(4, 4, 4, T, a, b);
}

pub fn orthographic(comptime T: type, left: T, right: T, bottom: T, top: T, near: T, far: T) [4][4]T {
    const widthRatio = 1 / (right - left);
    const heightRatio = 1 / (top - bottom);
    const depthRatio = 1 / (far - near);
    const tx = -(right + left) * widthRatio;
    const ty = -(top + bottom) * heightRatio;
    const tz = -(far + near) * depthRatio;
    return .{
        .{ 2 * widthRatio, 0, 0, 0 },
        .{ 0, 2 * heightRatio, 0, 0 },
        .{ 0, 0, -2 * depthRatio, 0 },
        .{ tx, ty, tz, 1 },
    };
}

pub fn perspective(comptime T: type, fovRadians: T, aspect: T, near: T, far: T) [4][4]T {
    const f = @tan(std.math.pi * 0.5 - 0.5 * fovRadians);
    const rangeInv = 1.0 / (near - far);

    return .{
        .{ f / aspect, 0, 0, 0 },
        .{ 0, f, 0, 0 },
        .{ 0, 0, (near + far) * rangeInv, -1 },
        .{ 0, 0, near * far * rangeInv * 2, 0 },
    };
}

pub fn lookAt(comptime T: type, eye: @Vector(3, T), target: @Vector(3, T), up: @Vector(3, T)) [4][4]T {
    const f = vec.normalize(3, T, target - eye);
    const s = vec.normalize(3, T, vec.cross(T, f, vec.normalize(3, T, up)));
    const u = vec.cross(T, s, f);

    var res: [4][4]T = undefined;

    res[0][0] = s[0];
    res[1][0] = s[1];
    res[2][0] = s[2];
    res[3][0] = -@reduce(.Add, s * eye);
    res[0][1] = u[0];
    res[1][1] = u[1];
    res[2][1] = u[2];
    res[3][1] = -@reduce(.Add, u * eye);
    res[0][2] = -f[0];
    res[1][2] = -f[1];
    res[2][2] = -f[2];
    res[3][2] = @reduce(.Add, f * eye);
    res[0][3] = 0;
    res[1][3] = 0;
    res[2][3] = 0;
    res[3][3] = 1;

    return res;
}

const std = @import("std");
const vec = @import("./vec.zig");
const mat = @import("./mat.zig");
