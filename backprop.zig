pub fn layer_forward_sigmoid(inputs: []const f32, weights: ConstGrid(2, f32), biases: []const f32, outputs: []f32) void {
    for (outputs, 0..weights.size[1], biases) |*out, row_index, bias| {
        var sum: f32 = bias;
        for (inputs, weights.getRow(row_index)) |x, w| {
            sum += x * w;
        }
        out.* = sigmoid(sum);
    }
}

pub fn layer_forward_tanh(inputs: []const f32, weights: ConstGrid(2, f32), biases: []const f32, outputs: []f32) void {
    for (outputs, 0..weights.size[1], biases) |*out, row_index, bias| {
        var sum: f32 = bias;
        for (inputs, weights.getRow(row_index)) |x, w| {
            sum += x * w;
        }
        out.* = tanh(sum);
    }
}

pub fn layer_backward_tanh(inputs: []const f32, weights: ConstGrid(2, f32), outputs: []const f32, output_gradients: []const f32, input_gradients: []f32, weight_gradients: Grid(2, f32), bias_gradients: []f32) void {
    std.mem.set(f32, input_gradients, 0);
    weight_gradients.set(0);
    std.mem.set(f32, bias_gradients, 0);
    for (outputs, output_gradients, 0..weights.size[1], bias_gradients) |out, out_gradient, row_index, *bias_gradient| {
        // tanh gradient = 1 - tanh ^ 2, and our neuron's output is tanh
        const activation_gradient = (1.0 - out * out) * out_gradient;
        bias_gradient.* += activation_gradient;
        for (input_gradients, weight_gradients.getRow(row_index), inputs, weights.getRow(row_index)) |*xg, *wg, x, w| {
            xg.* += w * activation_gradient;
            wg.* += x * activation_gradient;
        }
    }
}

test "simple neural network forward pass" {
    const input = [_]f32{ 1, 2, 3 };
    const middle_weights = ConstGrid(2, f32){
        .data = &[_]f32{
            0.5,  0.4,  0.3,
            -0.5, -0.4, -0.3,
        },
        .size = .{ 3, 2 },
        .stride = .{3},
    };
    const output_weights = ConstGrid(2, f32){
        .data = &[_]f32{ 0.2, -0.2 },
        .size = .{ 2, 1 },
        .stride = .{2},
    };

    var middle: [2]f32 = undefined;
    layer_forward_sigmoid(&input, middle_weights, &.{ 0, 0 }, &middle);

    try std.testing.expectEqualSlices(f32, &.{ 9.00249540e-01, 9.97504815e-02 }, &middle);

    var output: [1]f32 = undefined;
    layer_forward_sigmoid(&middle, output_weights, &.{0}, &output);
    try std.testing.expectEqualSlices(f32, &.{5.39939641e-01}, &output);
}

pub fn sigmoid(x: f32) f32 {
    return 1.0 / (1.0 + @exp(-x));
}

pub fn tanh(x: f32) f32 {
    return (@exp(2.0 * x) - 1.0) / (@exp(2.0 * x) + 1.0);
}

pub fn tanh_gradient(x: f32) f32 {
    return ((@exp(2.0 * x) - 1.0) * (@exp(2.0 * x) - 1.0)) / ((@exp(2.0 * x) + 1.0) * (@exp(2.0 * x) + 1.0));
}

test tanh_gradient {
    var default_prng = std.rand.DefaultPrng.init(8564095);
    const prng = default_prng.random();
    for (0..5000) |_| {
        const value = prng.floatNorm(f32);
        try std.testing.expectApproxEqRel(tanh_gradient(value), tanh(value) * tanh(value), 0.00001);
    }
}

test "train neural network on xor function" {
    // set up random number generator with fixed seed
    var default_prng = std.rand.DefaultPrng.init(8564095);
    const prng = default_prng.random();

    // training data
    const inputs = &[_][2]f32{
        .{ -1, -1 },
        .{ -1, 1 },
        .{ 1, -1 },
        .{ 1, 1 },
    };
    const expected_outputs = &[_][1]f32{
        .{-1},
        .{1},
        .{1},
        .{-1},
    };

    // initialize weights
    var middle_weights = try Grid(2, f32).alloc(std.testing.allocator, .{ 2, 2 });
    defer middle_weights.free(std.testing.allocator);
    var middle_biases: [2]f32 = undefined;
    var output_weights = try Grid(2, f32).alloc(std.testing.allocator, .{ 2, 1 });
    defer output_weights.free(std.testing.allocator);
    var output_biases: [1]f32 = undefined;

    for (0..middle_weights.size[1]) |neuron_index| {
        for (middle_weights.getRow(neuron_index)) |*w| {
            w.* = prng.floatNorm(f32);
        }
    }
    for (&middle_biases) |*b| {
        b.* = prng.floatNorm(f32);
    }
    for (0..output_weights.size[1]) |neuron_index| {
        for (output_weights.getRow(neuron_index)) |*w| {
            w.* = prng.floatNorm(f32);
        }
    }
    for (&output_biases) |*b| {
        b.* = prng.floatNorm(f32);
    }

    // train
    const iterations = 1_000_000;
    for (0..iterations) |iteration| {
        const temperature = 0.01;

        var total_loss: f32 = 0;
        for (inputs, expected_outputs) |input, expected_output| {
            var middle: [2]f32 = undefined;
            layer_forward_tanh(&input, middle_weights.asConst(), &middle_biases, &middle);

            var output: [1]f32 = undefined;
            layer_forward_tanh(&middle, output_weights.asConst(), &output_biases, &output);

            total_loss += (output[0] - expected_output[0]) * (output[0] - expected_output[0]);

            var middle_gradients: [2]f32 = undefined;
            var output_weight_gradients: [1][2]f32 = undefined;
            const output_weight_gradients_grid = Grid(2, f32){
                .data = &output_weight_gradients[0],
                .size = .{ 2, 1 },
                .stride = .{2},
            };
            var output_bias_gradients: [1]f32 = undefined;
            layer_backward_tanh(
                &middle,
                output_weights.asConst(),
                &output,
                &.{2.0 * (output[0] - expected_output[0])},
                &middle_gradients,
                output_weight_gradients_grid,
                &output_bias_gradients,
            );

            var input_gradients: [2]f32 = undefined;
            var middle_weight_gradients: [2][2]f32 = undefined;
            const middle_weight_gradients_grid = Grid(2, f32){
                .data = &middle_weight_gradients[0],
                .size = .{ 2, 2 },
                .stride = .{2},
            };
            var middle_bias_gradients: [2]f32 = undefined;
            layer_backward_tanh(
                &input,
                middle_weights.asConst(),
                &middle,
                &middle_gradients,
                &input_gradients,
                middle_weight_gradients_grid,
                &middle_bias_gradients,
            );

            // gradient descent by moving neural networks parameters in the direction of less loss/error
            for (0..middle_weights.size[1]) |neuron_index| {
                for (middle_weights.getRow(neuron_index), middle_weight_gradients_grid.getRow(neuron_index)) |*weight, gradient| {
                    weight.* -= gradient * temperature;
                }
            }
            for (&middle_biases, &middle_bias_gradients) |*bias, gradient| {
                bias.* -= gradient * temperature;
            }
            for (0..output_weights.size[1]) |neuron_index| {
                for (output_weights.getRow(neuron_index), output_weight_gradients_grid.getRow(neuron_index)) |*weight, gradient| {
                    weight.* -= gradient * temperature;
                }
            }
            for (&output_biases, &output_bias_gradients) |*bias, gradient| {
                bias.* -= gradient * temperature;
            }
        }
        if (iteration % (iterations / 15) == 0) {
            std.debug.print("iteration {} loss = {}\n", .{ iteration, total_loss });
        }
    }

    // test that the network has learned xor
    for (inputs, expected_outputs) |input, expected_output| {
        var middle: [2]f32 = undefined;
        layer_forward_tanh(&input, middle_weights.asConst(), &middle_biases, &middle);

        var output: [1]f32 = undefined;
        layer_forward_tanh(&middle, output_weights.asConst(), &output_biases, &output);

        try std.testing.expectApproxEqAbs(expected_output[0], output[0], 0.1);
    }
}

const Grid = @import("./grid.zig").Grid;
const ConstGrid = @import("./grid.zig").ConstGrid;
const std = @import("std");
