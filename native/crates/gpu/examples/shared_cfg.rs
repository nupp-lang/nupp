// Execute the graph-produced WGSL and SPIR-V through the same device and ABI.
use std::{borrow::Cow, sync::mpsc};
fn main() {
    let root = std::env::args()
        .nth(1)
        .expect("shared_cfg ARTIFACT_DIRECTORY");
    let instance =
        wgpu::Instance::new(wgpu::InstanceDescriptor::new_without_display_handle_from_env());
    let adapter = pollster::block_on(instance.request_adapter(&Default::default())).unwrap();
    println!("adapter={:?}", adapter.get_info());
    let (device, queue) = pollster::block_on(adapter.request_device(&Default::default())).unwrap();
    let mut cases = 0;
    for name in ["mapAdd", "mapDiamond", "mapRotate"] {
        for suffix in ["wgsl", "spv"] {
            let path = format!("{root}/{name}.{suffix}");
            let binary = suffix.ends_with("spv");
            let shader = device.create_shader_module(wgpu::ShaderModuleDescriptor {
                label: Some(name),
                source: if binary {
                    let bytes = std::fs::read(&path).unwrap();
                    wgpu::ShaderSource::SpirV(Cow::Owned(
                        bytes
                            .chunks_exact(4)
                            .map(|w| u32::from_le_bytes(w.try_into().unwrap()))
                            .collect(),
                    ))
                } else {
                    wgpu::ShaderSource::Wgsl(Cow::Owned(std::fs::read_to_string(&path).unwrap()))
                },
            });
            let pipeline = device.create_compute_pipeline(&wgpu::ComputePipelineDescriptor {
                label: Some(name),
                layout: None,
                module: &shader,
                entry_point: None,
                compilation_options: Default::default(),
                cache: None,
            });
            for count in [0u32, 1, 3, 255, 256, 257, 1025] {
                for seed in [0u32, 1, 0x8000_0000, u32::MAX] {
                    let input_offset = 3u32;
                    let output_offset = 5u32;
                    let size = (count + 10) as u64 * 4;
                    let buffer = |usage| {
                        device.create_buffer(&wgpu::BufferDescriptor {
                            label: None,
                            size,
                            usage,
                            mapped_at_creation: false,
                        })
                    };
                    let input = buffer(wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_DST);
                    let output = buffer(
                        wgpu::BufferUsages::STORAGE
                            | wgpu::BufferUsages::COPY_SRC
                            | wgpu::BufferUsages::COPY_DST,
                    );
                    let readback =
                        buffer(wgpu::BufferUsages::MAP_READ | wgpu::BufferUsages::COPY_DST);
                    let uniform = device.create_buffer(&wgpu::BufferDescriptor {
                        label: None,
                        size: 32,
                        usage: wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
                        mapped_at_creation: false,
                    });
                    let source_value = |i: u32| [0, 1, u32::MAX, 0x8000_0000, 17][i as usize % 5];
                    let mut values = vec![0xdead_beefu32; (count + 10) as usize];
                    for i in 0..count {
                        values[(i + input_offset) as usize] = source_value(i);
                    }
                    queue.write_buffer(
                        &input,
                        0,
                        &values
                            .iter()
                            .flat_map(|v| v.to_le_bytes())
                            .collect::<Vec<_>>(),
                    );
                    queue.write_buffer(&output, 0, &vec![0xa5; size as usize]);
                    let uniforms = [count, count, count, input_offset, output_offset, seed, 0, 0];
                    queue.write_buffer(
                        &uniform,
                        0,
                        &uniforms
                            .into_iter()
                            .flat_map(u32::to_le_bytes)
                            .collect::<Vec<_>>(),
                    );
                    // WGSL binds everything in group 0; SPIR-V keeps the native
                    // crate's sets: read-only buffers, writable buffers, uniforms.
                    fn entry(binding: u32, resource: &wgpu::Buffer) -> wgpu::BindGroupEntry<'_> {
                        wgpu::BindGroupEntry {
                            binding,
                            resource: resource.as_entire_binding(),
                        }
                    }
                    let groups: Vec<wgpu::BindGroup> = if binary {
                        [(0, &input), (1, &output), (2, &uniform)]
                            .iter()
                            .map(|(set, buffer)| {
                                device.create_bind_group(&wgpu::BindGroupDescriptor {
                                    label: None,
                                    layout: &pipeline.get_bind_group_layout(*set),
                                    entries: &[entry(0, buffer)],
                                })
                            })
                            .collect()
                    } else {
                        vec![device.create_bind_group(&wgpu::BindGroupDescriptor {
                            label: None,
                            layout: &pipeline.get_bind_group_layout(0),
                            entries: &[entry(0, &input), entry(1, &output), entry(2, &uniform)],
                        })]
                    };
                    let mut encoder = device.create_command_encoder(&Default::default());
                    {
                        let mut pass = encoder.begin_compute_pass(&Default::default());
                        pass.set_pipeline(&pipeline);
                        for (set, group) in groups.iter().enumerate() {
                            pass.set_bind_group(set as u32, group, &[]);
                        }
                        let groups = count.div_ceil(256).max(1);
                        let x = groups.min(2);
                        pass.dispatch_workgroups(x, groups.div_ceil(x), 1);
                    }
                    encoder.copy_buffer_to_buffer(&output, 0, &readback, 0, size);
                    queue.submit([encoder.finish()]);
                    let (tx, rx) = mpsc::channel();
                    readback.map_async(wgpu::MapMode::Read, .., move |v| tx.send(v).unwrap());
                    device.poll(wgpu::PollType::wait_indefinitely()).unwrap();
                    rx.recv().unwrap().unwrap();
                    {
                        let data = readback.get_mapped_range(..).unwrap();
                        for (at, bytes) in data.chunks_exact(4).enumerate() {
                            let at = at as u32;
                            let expected = if at < output_offset || at >= output_offset + count {
                                0xa5a5_a5a5
                            } else {
                                let value = source_value(at - output_offset);
                                match name {
                                    "mapAdd" => value.wrapping_add(seed),
                                    "mapDiamond" => {
                                        if value < seed {
                                            value.wrapping_sub(1)
                                        } else {
                                            value.wrapping_sub(seed)
                                        }
                                    }
                                    "mapRotate" => seed.wrapping_sub(value),
                                    _ => unreachable!(),
                                }
                            };
                            assert_eq!(
                                u32::from_le_bytes(bytes.try_into().unwrap()),
                                expected,
                                "{name} {suffix} count={count} seed={seed} at={at}"
                            );
                        }
                    }
                    readback.unmap();
                    cases += 1;
                }
            }
        }
    }
    println!("shared CFG GPU: {cases} cases passed");
}
