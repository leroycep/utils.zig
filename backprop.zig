test "simple neural network forward pass" {
    const input = &[_]f32{ 1, 2, 3 };
    const middle_weights = [2][3]f32{
        .{ 0.5, 0.4, 0.3 },
        .{ -0.5, -0.4, -0.3 },
    };
    const output_weights = [2]f32{ 0.2, -0.2 };

    var middle: [2]f32 = undefined;
    for (&middle, middle_weights) |*out, weights| {
        var sum: f32 = 0;
        for (input, weights) |x, w| {
            sum += x * w;
        }
        out.* = sigmoid(sum);
    }

    try std.testing.expectEqualSlices(f32, &.{ 9.00249540e-01, 9.97504815e-02 }, &middle);

    var output: [1]f32 = undefined;
    for (&output) |*out| {
        var sum: f32 = 0;
        for (middle, output_weights) |x, w| {
            sum += x * w;
        }
        out.* = sigmoid(sum);
    }
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
    var middle_weights: [2][2]f32 = undefined;
    var output_weights: [1][2]f32 = undefined;

    for (&middle_weights) |*neuron_weights| {
        for (neuron_weights) |*w| {
            w.* = prng.floatNorm(f32);
        }
    }
    for (&output_weights) |*neuron_weights| {
        for (neuron_weights) |*w| {
            w.* = prng.floatNorm(f32);
        }
    }

    // train
    const iterations = 1_000_000;
    for (0..iterations) |iteration| {
        const temperature = 0.01;

        var total_loss: f32 = 0;
        for (inputs, expected_outputs) |input, expected_output| {
            var middle: [2]f32 = undefined;
            for (&middle, middle_weights) |*out, weights| {
                var sum: f32 = 0;
                for (input, weights) |x, w| {
                    sum += x * w;
                }
                out.* = tanh(sum);
            }

            var output: [1]f32 = undefined;
            for (&output, &output_weights) |*out, weights| {
                var sum: f32 = 0;
                for (middle, weights) |x, w| {
                    sum += x * w;
                }
                out.* = tanh(sum);
            }

            total_loss += (output[0] - expected_output[0]) * (output[0] - expected_output[0]);

            const loss_gradient = 2.0;
            const output0_gradient = loss_gradient * (output[0] - expected_output[0]);

            var output_input_gradients: [1][2]f32 = undefined;
            var output_weight_gradients: [1][2]f32 = undefined;
            for (&output_weights, output, &output_input_gradients, &output_weight_gradients) |weights, y, *input_gradients, *weight_gradients| {
                std.mem.set(f32, input_gradients, 0);
                std.mem.set(f32, weight_gradients, 0);
                // tanh gradient = 1 - tanh ^ 2, and our neuron's output is tanh
                const activation_gradient = (1.0 - y * y) * output0_gradient;
                for (input_gradients, weight_gradients, middle, weights) |*xg, *wg, x, w| {
                    xg.* += w * activation_gradient;
                    wg.* += x * activation_gradient;
                }
            }

            var middle_input_gradients: [2][2]f32 = undefined;
            var middle_weight_gradients: [2][2]f32 = undefined;
            for (&middle_weights, middle, &middle_input_gradients, &middle_weight_gradients, 0..) |weights, y, *input_gradients, *weight_gradients, i| {
                std.mem.set(f32, input_gradients, 0);
                std.mem.set(f32, weight_gradients, 0);

                // Get the total gradient for each of the outputs that relies on this neuron
                var output_gradient: f32 = 0;
                for (output_input_gradients) |og| {
                    output_gradient += og[i];
                }

                // tanh gradient = 1 - tanh ^ 2, and our neuron's output is tanh
                const activation_gradient = (1.0 - y * y) * output_gradient;
                for (input_gradients, weight_gradients, input, weights) |*xg, *wg, x, w| {
                    xg.* += w * activation_gradient;
                    wg.* += x * activation_gradient;
                }
            }

            // gradient descent by moving neural networks parameters in the direction of less loss/error
            for (&middle_weights, middle_weight_gradients) |*layer_weights, layer_gradients| {
                for (layer_weights, &layer_gradients) |*weight, gradient| {
                    weight.* -= gradient * temperature;
                }
            }
            for (&output_weights, output_weight_gradients) |*layer_weights, layer_gradients| {
                for (layer_weights, &layer_gradients) |*weight, gradient| {
                    weight.* -= gradient * temperature;
                }
            }
        }
        if (iteration % (iterations / 15) == 0) {
            std.debug.print("iteration {} loss = {}\n", .{ iteration, total_loss });
        }
    }

    // test that the network has learned xor
    for (inputs, expected_outputs) |input, expected_output| {
        var middle: [2]f32 = undefined;
        for (&middle, middle_weights) |*out, weights| {
            var sum: f32 = 0;
            for (input, weights) |x, w| {
                sum += x * w;
            }
            out.* = tanh(sum);
        }

        var output: [1]f32 = undefined;
        for (&output, &output_weights) |*out, weights| {
            var sum: f32 = 0;
            for (middle, weights) |x, w| {
                sum += x * w;
            }
            out.* = tanh(sum);
        }

        try std.testing.expectApproxEqAbs(expected_output[0], output[0], 0.1);
    }
}

// pub const Operation = union(enum) {
//     add: struct {
//         input: [2]ConstGrid(N, T),
//         output: Grid(N, T),
//     },
//     sub,
//     mul,
//     div,
// };

const Grid = @import("./grid.zig").ConstGrid;
const ConstGrid = @import("./grid.zig").ConstGrid;
const std = @import("std");
