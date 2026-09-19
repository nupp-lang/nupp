struct NuppUniforms {
    count: u32,
    input_count: u32,
    output_count: u32,
    input_offset: u32,
    output_offset: u32,
}

@group(0) @binding(0) var<storage, read> input: array<u32>;
@group(0) @binding(1) var<storage, read_write> output: array<u32>;
@group(0) @binding(2) var<uniform> uniforms: NuppUniforms;

@compute @workgroup_size(256)
fn ks_literal_gpu(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let dispatch_index = global_id.x;
    if (dispatch_index >= uniforms.count) {
        return;
    }
    var v1_value: u32 = input[uniforms.input_offset + dispatch_index];
    {
        var nupp_for_counter_1: i32 = 1;
        let nupp_for_last_1: i32 = 64;
        loop {
            if (nupp_for_counter_1 > nupp_for_last_1) { break; }
            var v4__: i32 = nupp_for_counter_1;
            v1_value = (v1_value + 1u);
            continuing {
                let nupp_for_done_1 = nupp_for_counter_1 == nupp_for_last_1;
                if (!nupp_for_done_1) { nupp_for_counter_1 = nupp_for_counter_1 + 1; }
                break if nupp_for_done_1;
            }
        }
    }
    {
        v1_value = (v1_value + 1u);
    }
    {
        v1_value = (v1_value + 1u);
    }
    {
        v1_value = (v1_value + 1u);
    }
    {
        v1_value = (v1_value + 1u);
    }
    output[uniforms.output_offset + dispatch_index] = v1_value;
}