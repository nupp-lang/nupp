// Untimed conformance for compiler-emitted WGSL, independent of SPIR-V.
// The argument names the directory containing the four counted-loop shaders.
use std::{borrow::Cow, sync::mpsc};
fn main() {
    let root = std::env::args()
        .nth(1)
        .expect("usage: counted_wgsl ARTIFACT_DIRECTORY");
    let instance =
        wgpu::Instance::new(wgpu::InstanceDescriptor::new_without_display_handle_from_env());
    let adapter = pollster::block_on(instance.request_adapter(&Default::default())).unwrap();
    println!("adapter={:?}", adapter.get_info());
    let (device, queue) =
        pollster::block_on(adapter.request_device(&wgpu::DeviceDescriptor::default())).unwrap();
    let count = 257u32;
    let buffer = |size, usage| {
        device.create_buffer(&wgpu::BufferDescriptor {
            label: None,
            size,
            usage,
            mapped_at_creation: false,
        })
    };
    let input = buffer(
        count as u64 * 4,
        wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_DST,
    );
    let output = buffer(
        count as u64 * 4,
        wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC,
    );
    let uniform = buffer(
        32,
        wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
    );
    let readback = buffer(
        count as u64 * 4,
        wgpu::BufferUsages::MAP_READ | wgpu::BufferUsages::COPY_DST,
    );
    let initial: Vec<u8> = (0..count)
        .flat_map(|i| (i * 17 + 3).to_le_bytes())
        .collect();
    queue.write_buffer(&input, 0, &initial);
    let mut checked = 0;
    for name in ["literal", "boundaries", "snapshots", "control"] {
        let source = std::fs::read_to_string(format!("{root}/{name}.wgsl")).unwrap();
        let shader = device.create_shader_module(wgpu::ShaderModuleDescriptor {
            label: Some(name),
            source: wgpu::ShaderSource::Wgsl(Cow::Owned(source)),
        });
        let pipeline = device.create_compute_pipeline(&wgpu::ComputePipelineDescriptor {
            label: Some(name),
            layout: None,
            module: &shader,
            entry_point: None,
            compilation_options: Default::default(),
            cache: None,
        });
        let group = device.create_bind_group(&wgpu::BindGroupDescriptor {
            label: None,
            layout: &pipeline.get_bind_group_layout(0),
            entries: &[
                wgpu::BindGroupEntry {
                    binding: 0,
                    resource: input.as_entire_binding(),
                },
                wgpu::BindGroupEntry {
                    binding: 1,
                    resource: output.as_entire_binding(),
                },
                wgpu::BindGroupEntry {
                    binding: 2,
                    resource: uniform.as_entire_binding(),
                },
            ],
        });
        let cases: Vec<(i32, i32)> = match name {
            "literal" => vec![(0, 0)],
            "snapshots" => vec![(1, 4), (3, 2)],
            _ => vec![
                (1, 4),
                (0, 0),
                (3, 2),
                (-2, 1),
                (2147483645, 2147483647),
                (-2147483648, -2147483646),
            ],
        };
        for (first, last) in cases {
            let values = [count, count, count, 0, 0, first as u32, last as u32, 0];
            queue.write_buffer(
                &uniform,
                0,
                &values
                    .into_iter()
                    .flat_map(u32::to_le_bytes)
                    .collect::<Vec<_>>(),
            );
            let mut encoder = device.create_command_encoder(&Default::default());
            {
                let mut pass = encoder.begin_compute_pass(&Default::default());
                pass.set_pipeline(&pipeline);
                pass.set_bind_group(0, &group, &[]);
                pass.dispatch_workgroups(count.div_ceil(256), 1, 1);
            }
            encoder.copy_buffer_to_buffer(&output, 0, &readback, 0, count as u64 * 4);
            queue.submit([encoder.finish()]);
            let (tx, rx) = mpsc::channel();
            readback.map_async(wgpu::MapMode::Read, .., move |v| tx.send(v).unwrap());
            device.poll(wgpu::PollType::wait_indefinitely()).unwrap();
            rx.recv().unwrap().unwrap();
            let expected: u32 = match name {
                "literal" => 68,
                "snapshots" => {
                    1000 + if first <= last {
                        (i64::from(last) - i64::from(first) + 1) as u32
                    } else {
                        0
                    }
                }
                "boundaries" => (i64::from(first)..=i64::from(last))
                    .map(|i| {
                        1 + if i < 0 { 100 } else { 0 } + if i == 2147483647 { 1000 } else { 0 }
                    })
                    .sum(),
                _ => {
                    let mut n = 0;
                    for i in i64::from(first)..=i64::from(last) {
                        if i == i64::from(first) {
                            continue;
                        }
                        n += 11;
                        if i == 3 {
                            break;
                        }
                    }
                    n
                }
            };
            {
                let data = readback.get_mapped_range(..).unwrap();
                for (i, bytes) in data.chunks_exact(4).enumerate() {
                    assert_eq!(
                        u32::from_le_bytes(bytes.try_into().unwrap()),
                        i as u32 * 17 + 3 + expected,
                        "{name} {first}..{last} index{i}"
                    );
                }
            }
            readback.unmap();
            checked += 1;
        }
    }
    println!(
        "WGSL counted loops: {checked} cases, {} output values checked",
        checked * count
    );
}
