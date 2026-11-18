/* The wgpu header layout probe: a test-only program that prints, as JSON,
 * the size, alignment and field offsets of every wgpu-native structure the
 * runtime lays out for itself (nupp.runtime.provider.wgpumemory).
 * .github/scripts/test-wgpu-conformance.py compiles it against the exact
 * headers of the pinned release, and wgpu-conformance.lua then holds each of
 * the runtime's layouts to what these headers say. The output is one object
 * keyed by the runtime's name for each layout:
 *
 *   {
 *   "WGPUStringView":{"size":16,"alignment":8,"fields":{"data":0,"length":8}},
 *   ...
 *   }
 *
 * A layout lists the fields the runtime declares, which need not be all of
 * the C structure's. */

#include "wgpu.h"

#include <stddef.h>
#include <stdio.h>

/* Opens the entry for layout N, measured from C type T, through the opening
 * brace of its fields. The entry is closed by printing "}}". */
#define TYPE(N, T)                                                             \
  printf("\"" #N "\":{\"size\":%zu,\"alignment\":%zu,\"fields\":{", sizeof(T), \
         _Alignof(T))

/* One field's offset; fields are separated by the caller's commas. */
#define FIELD(T, F) printf("\"" #F "\":%zu", offsetof(T, F))

int main (void) {
  puts("{");
  TYPE(WGPUNativeDisplayHandle, WGPUNativeDisplayHandle);
  FIELD(WGPUNativeDisplayHandle, type);
  putchar(',');
  /* The handle data is a union of platform handles, which the runtime
   * declares as two plain words starting at this offset. */
  printf("\"words\":%zu", offsetof(WGPUNativeDisplayHandle, data));
  puts("}},");

  TYPE(WGPUStringView, WGPUStringView);
  FIELD(WGPUStringView, data);
  putchar(',');
  FIELD(WGPUStringView, length);
  puts("}},");

  TYPE(WGPUChainedStruct, WGPUChainedStruct);
  FIELD(WGPUChainedStruct, next);
  putchar(',');
  FIELD(WGPUChainedStruct, sType);
  puts("}},");

  TYPE(WGPUFuture, WGPUFuture);
  FIELD(WGPUFuture, id);
  puts("}},");

  /* The callback-info structures that carry a mode share one layout, which
   * the runtime declares once as WGPUCallbackInfo. */
  TYPE(WGPUCallbackInfo, WGPURequestAdapterCallbackInfo);
  FIELD(WGPURequestAdapterCallbackInfo, nextInChain);
  putchar(',');
  FIELD(WGPURequestAdapterCallbackInfo, mode);
  putchar(',');
  FIELD(WGPURequestAdapterCallbackInfo, callback);
  putchar(',');
  FIELD(WGPURequestAdapterCallbackInfo, userdata1);
  putchar(',');
  FIELD(WGPURequestAdapterCallbackInfo, userdata2);
  puts("}},");

  TYPE(WGPUUncapturedErrorCallbackInfo, WGPUUncapturedErrorCallbackInfo);
  FIELD(WGPUUncapturedErrorCallbackInfo, nextInChain);
  putchar(',');
  FIELD(WGPUUncapturedErrorCallbackInfo, callback);
  putchar(',');
  FIELD(WGPUUncapturedErrorCallbackInfo, userdata1);
  putchar(',');
  FIELD(WGPUUncapturedErrorCallbackInfo, userdata2);
  puts("}},");

  TYPE(WGPUInstanceExtras, WGPUInstanceExtras);
  FIELD(WGPUInstanceExtras, chain);
  putchar(',');
  FIELD(WGPUInstanceExtras, backends);
  putchar(',');
  FIELD(WGPUInstanceExtras, flags);
  putchar(',');
  FIELD(WGPUInstanceExtras, dx12ShaderCompiler);
  putchar(',');
  FIELD(WGPUInstanceExtras, gles3MinorVersion);
  putchar(',');
  FIELD(WGPUInstanceExtras, glFenceBehaviour);
  putchar(',');
  FIELD(WGPUInstanceExtras, dxcPath);
  putchar(',');
  FIELD(WGPUInstanceExtras, dxcMaxShaderModel);
  putchar(',');
  FIELD(WGPUInstanceExtras, dx12PresentationSystem);
  putchar(',');
  FIELD(WGPUInstanceExtras, budgetForDeviceCreation);
  putchar(',');
  FIELD(WGPUInstanceExtras, budgetForDeviceLoss);
  putchar(',');
  FIELD(WGPUInstanceExtras, displayHandle);
  puts("}},");

  TYPE(WGPUInstanceDescriptor, WGPUInstanceDescriptor);
  FIELD(WGPUInstanceDescriptor, nextInChain);
  putchar(',');
  FIELD(WGPUInstanceDescriptor, requiredFeatureCount);
  putchar(',');
  FIELD(WGPUInstanceDescriptor, requiredFeatures);
  putchar(',');
  FIELD(WGPUInstanceDescriptor, requiredLimits);
  puts("}},");

  TYPE(WGPURequestAdapterOptions, WGPURequestAdapterOptions);
  FIELD(WGPURequestAdapterOptions, nextInChain);
  putchar(',');
  FIELD(WGPURequestAdapterOptions, featureLevel);
  putchar(',');
  FIELD(WGPURequestAdapterOptions, powerPreference);
  putchar(',');
  FIELD(WGPURequestAdapterOptions, forceFallbackAdapter);
  putchar(',');
  FIELD(WGPURequestAdapterOptions, backendType);
  putchar(',');
  FIELD(WGPURequestAdapterOptions, compatibleSurface);
  puts("}},");

  TYPE(WGPUAdapterInfo, WGPUAdapterInfo);
  FIELD(WGPUAdapterInfo, nextInChain);
  putchar(',');
  FIELD(WGPUAdapterInfo, vendor);
  putchar(',');
  FIELD(WGPUAdapterInfo, architecture);
  putchar(',');
  FIELD(WGPUAdapterInfo, device);
  putchar(',');
  FIELD(WGPUAdapterInfo, description);
  putchar(',');
  FIELD(WGPUAdapterInfo, backendType);
  putchar(',');
  FIELD(WGPUAdapterInfo, adapterType);
  putchar(',');
  FIELD(WGPUAdapterInfo, vendorID);
  putchar(',');
  FIELD(WGPUAdapterInfo, deviceID);
  putchar(',');
  FIELD(WGPUAdapterInfo, subgroupMinSize);
  putchar(',');
  FIELD(WGPUAdapterInfo, subgroupMaxSize);
  puts("}},");

  TYPE(WGPULimits, WGPULimits);
  FIELD(WGPULimits, nextInChain);
  putchar(',');
  FIELD(WGPULimits, maxTextureDimension1D);
  putchar(',');
  FIELD(WGPULimits, maxTextureDimension2D);
  putchar(',');
  FIELD(WGPULimits, maxTextureDimension3D);
  putchar(',');
  FIELD(WGPULimits, maxTextureArrayLayers);
  putchar(',');
  FIELD(WGPULimits, maxBindGroups);
  putchar(',');
  FIELD(WGPULimits, maxBindGroupsPlusVertexBuffers);
  putchar(',');
  FIELD(WGPULimits, maxBindingsPerBindGroup);
  putchar(',');
  FIELD(WGPULimits, maxDynamicUniformBuffersPerPipelineLayout);
  putchar(',');
  FIELD(WGPULimits, maxDynamicStorageBuffersPerPipelineLayout);
  putchar(',');
  FIELD(WGPULimits, maxSampledTexturesPerShaderStage);
  putchar(',');
  FIELD(WGPULimits, maxSamplersPerShaderStage);
  putchar(',');
  FIELD(WGPULimits, maxStorageBuffersPerShaderStage);
  putchar(',');
  FIELD(WGPULimits, maxStorageTexturesPerShaderStage);
  putchar(',');
  FIELD(WGPULimits, maxUniformBuffersPerShaderStage);
  putchar(',');
  FIELD(WGPULimits, maxUniformBufferBindingSize);
  putchar(',');
  FIELD(WGPULimits, maxStorageBufferBindingSize);
  putchar(',');
  FIELD(WGPULimits, minUniformBufferOffsetAlignment);
  putchar(',');
  FIELD(WGPULimits, minStorageBufferOffsetAlignment);
  putchar(',');
  FIELD(WGPULimits, maxVertexBuffers);
  putchar(',');
  FIELD(WGPULimits, maxBufferSize);
  putchar(',');
  FIELD(WGPULimits, maxVertexAttributes);
  putchar(',');
  FIELD(WGPULimits, maxVertexBufferArrayStride);
  putchar(',');
  FIELD(WGPULimits, maxInterStageShaderVariables);
  putchar(',');
  FIELD(WGPULimits, maxColorAttachments);
  putchar(',');
  FIELD(WGPULimits, maxColorAttachmentBytesPerSample);
  putchar(',');
  FIELD(WGPULimits, maxComputeWorkgroupStorageSize);
  putchar(',');
  FIELD(WGPULimits, maxComputeInvocationsPerWorkgroup);
  putchar(',');
  FIELD(WGPULimits, maxComputeWorkgroupSizeX);
  putchar(',');
  FIELD(WGPULimits, maxComputeWorkgroupSizeY);
  putchar(',');
  FIELD(WGPULimits, maxComputeWorkgroupSizeZ);
  putchar(',');
  FIELD(WGPULimits, maxComputeWorkgroupsPerDimension);
  putchar(',');
  FIELD(WGPULimits, maxImmediateSize);
  puts("}},");

  TYPE(WGPUQueueDescriptor, WGPUQueueDescriptor);
  FIELD(WGPUQueueDescriptor, nextInChain);
  putchar(',');
  FIELD(WGPUQueueDescriptor, label);
  puts("}},");

  TYPE(WGPUDeviceDescriptor, WGPUDeviceDescriptor);
  FIELD(WGPUDeviceDescriptor, nextInChain);
  putchar(',');
  FIELD(WGPUDeviceDescriptor, label);
  putchar(',');
  FIELD(WGPUDeviceDescriptor, requiredFeatureCount);
  putchar(',');
  FIELD(WGPUDeviceDescriptor, requiredFeatures);
  putchar(',');
  FIELD(WGPUDeviceDescriptor, requiredLimits);
  putchar(',');
  FIELD(WGPUDeviceDescriptor, defaultQueue);
  putchar(',');
  FIELD(WGPUDeviceDescriptor, deviceLostCallbackInfo);
  putchar(',');
  FIELD(WGPUDeviceDescriptor, uncapturedErrorCallbackInfo);
  puts("}},");

  TYPE(WGPUBufferDescriptor, WGPUBufferDescriptor);
  FIELD(WGPUBufferDescriptor, nextInChain);
  putchar(',');
  FIELD(WGPUBufferDescriptor, label);
  putchar(',');
  FIELD(WGPUBufferDescriptor, usage);
  putchar(',');
  FIELD(WGPUBufferDescriptor, size);
  putchar(',');
  FIELD(WGPUBufferDescriptor, mappedAtCreation);
  puts("}},");

  TYPE(WGPUBufferBindingLayout, WGPUBufferBindingLayout);
  FIELD(WGPUBufferBindingLayout, nextInChain);
  putchar(',');
  FIELD(WGPUBufferBindingLayout, type);
  putchar(',');
  FIELD(WGPUBufferBindingLayout, hasDynamicOffset);
  putchar(',');
  FIELD(WGPUBufferBindingLayout, minBindingSize);
  puts("}},");

  TYPE(WGPUSamplerBindingLayout, WGPUSamplerBindingLayout);
  FIELD(WGPUSamplerBindingLayout, nextInChain);
  putchar(',');
  FIELD(WGPUSamplerBindingLayout, type);
  puts("}},");

  TYPE(WGPUTextureBindingLayout, WGPUTextureBindingLayout);
  FIELD(WGPUTextureBindingLayout, nextInChain);
  putchar(',');
  FIELD(WGPUTextureBindingLayout, sampleType);
  putchar(',');
  FIELD(WGPUTextureBindingLayout, viewDimension);
  putchar(',');
  FIELD(WGPUTextureBindingLayout, multisampled);
  puts("}},");

  TYPE(WGPUStorageTextureBindingLayout, WGPUStorageTextureBindingLayout);
  FIELD(WGPUStorageTextureBindingLayout, nextInChain);
  putchar(',');
  FIELD(WGPUStorageTextureBindingLayout, access);
  putchar(',');
  FIELD(WGPUStorageTextureBindingLayout, format);
  putchar(',');
  FIELD(WGPUStorageTextureBindingLayout, viewDimension);
  puts("}},");

  TYPE(WGPUBindGroupLayoutEntry, WGPUBindGroupLayoutEntry);
  FIELD(WGPUBindGroupLayoutEntry, nextInChain);
  putchar(',');
  FIELD(WGPUBindGroupLayoutEntry, binding);
  putchar(',');
  FIELD(WGPUBindGroupLayoutEntry, visibility);
  putchar(',');
  FIELD(WGPUBindGroupLayoutEntry, bindingArraySize);
  putchar(',');
  FIELD(WGPUBindGroupLayoutEntry, buffer);
  putchar(',');
  FIELD(WGPUBindGroupLayoutEntry, sampler);
  putchar(',');
  FIELD(WGPUBindGroupLayoutEntry, texture);
  putchar(',');
  FIELD(WGPUBindGroupLayoutEntry, storageTexture);
  puts("}},");

  TYPE(WGPUBindGroupLayoutDescriptor, WGPUBindGroupLayoutDescriptor);
  FIELD(WGPUBindGroupLayoutDescriptor, nextInChain);
  putchar(',');
  FIELD(WGPUBindGroupLayoutDescriptor, label);
  putchar(',');
  FIELD(WGPUBindGroupLayoutDescriptor, entryCount);
  putchar(',');
  FIELD(WGPUBindGroupLayoutDescriptor, entries);
  puts("}},");

  TYPE(WGPUPipelineLayoutDescriptor, WGPUPipelineLayoutDescriptor);
  FIELD(WGPUPipelineLayoutDescriptor, nextInChain);
  putchar(',');
  FIELD(WGPUPipelineLayoutDescriptor, label);
  putchar(',');
  FIELD(WGPUPipelineLayoutDescriptor, bindGroupLayoutCount);
  putchar(',');
  FIELD(WGPUPipelineLayoutDescriptor, bindGroupLayouts);
  putchar(',');
  FIELD(WGPUPipelineLayoutDescriptor, immediateSize);
  puts("}},");

  TYPE(WGPUShaderSourceSPIRV, WGPUShaderSourceSPIRV);
  FIELD(WGPUShaderSourceSPIRV, chain);
  putchar(',');
  FIELD(WGPUShaderSourceSPIRV, codeSize);
  putchar(',');
  FIELD(WGPUShaderSourceSPIRV, code);
  puts("}},");

  TYPE(WGPUShaderSourceWGSL, WGPUShaderSourceWGSL);
  FIELD(WGPUShaderSourceWGSL, chain);
  putchar(',');
  FIELD(WGPUShaderSourceWGSL, code);
  puts("}},");

  TYPE(WGPUShaderModuleDescriptor, WGPUShaderModuleDescriptor);
  FIELD(WGPUShaderModuleDescriptor, nextInChain);
  putchar(',');
  FIELD(WGPUShaderModuleDescriptor, label);
  puts("}},");

  TYPE(WGPUComputeState, WGPUComputeState);
  FIELD(WGPUComputeState, nextInChain);
  putchar(',');
  FIELD(WGPUComputeState, module);
  putchar(',');
  FIELD(WGPUComputeState, entryPoint);
  putchar(',');
  FIELD(WGPUComputeState, constantCount);
  putchar(',');
  FIELD(WGPUComputeState, constants);
  puts("}},");

  TYPE(WGPUComputePipelineDescriptor, WGPUComputePipelineDescriptor);
  FIELD(WGPUComputePipelineDescriptor, nextInChain);
  putchar(',');
  FIELD(WGPUComputePipelineDescriptor, label);
  putchar(',');
  FIELD(WGPUComputePipelineDescriptor, layout);
  putchar(',');
  FIELD(WGPUComputePipelineDescriptor, compute);
  puts("}},");

  TYPE(WGPUBindGroupEntry, WGPUBindGroupEntry);
  FIELD(WGPUBindGroupEntry, nextInChain);
  putchar(',');
  FIELD(WGPUBindGroupEntry, binding);
  putchar(',');
  FIELD(WGPUBindGroupEntry, buffer);
  putchar(',');
  FIELD(WGPUBindGroupEntry, offset);
  putchar(',');
  FIELD(WGPUBindGroupEntry, size);
  putchar(',');
  FIELD(WGPUBindGroupEntry, sampler);
  putchar(',');
  FIELD(WGPUBindGroupEntry, textureView);
  puts("}},");

  TYPE(WGPUBindGroupDescriptor, WGPUBindGroupDescriptor);
  FIELD(WGPUBindGroupDescriptor, nextInChain);
  putchar(',');
  FIELD(WGPUBindGroupDescriptor, label);
  putchar(',');
  FIELD(WGPUBindGroupDescriptor, layout);
  putchar(',');
  FIELD(WGPUBindGroupDescriptor, entryCount);
  putchar(',');
  FIELD(WGPUBindGroupDescriptor, entries);
  puts("}},");

  TYPE(WGPUCommandEncoderDescriptor, WGPUCommandEncoderDescriptor);
  FIELD(WGPUCommandEncoderDescriptor, nextInChain);
  putchar(',');
  FIELD(WGPUCommandEncoderDescriptor, label);
  puts("}},");

  TYPE(WGPUCommandBufferDescriptor, WGPUCommandBufferDescriptor);
  FIELD(WGPUCommandBufferDescriptor, nextInChain);
  putchar(',');
  FIELD(WGPUCommandBufferDescriptor, label);
  puts("}},");

  TYPE(WGPUPassTimestampWrites, WGPUPassTimestampWrites);
  FIELD(WGPUPassTimestampWrites, nextInChain);
  putchar(',');
  FIELD(WGPUPassTimestampWrites, querySet);
  putchar(',');
  FIELD(WGPUPassTimestampWrites, beginningOfPassWriteIndex);
  putchar(',');
  FIELD(WGPUPassTimestampWrites, endOfPassWriteIndex);
  puts("}},");

  TYPE(WGPUComputePassDescriptor, WGPUComputePassDescriptor);
  FIELD(WGPUComputePassDescriptor, nextInChain);
  putchar(',');
  FIELD(WGPUComputePassDescriptor, label);
  putchar(',');
  FIELD(WGPUComputePassDescriptor, timestampWrites);
  puts("}},");

  TYPE(WGPUQuerySetDescriptor, WGPUQuerySetDescriptor);
  FIELD(WGPUQuerySetDescriptor, nextInChain);
  putchar(',');
  FIELD(WGPUQuerySetDescriptor, label);
  putchar(',');
  FIELD(WGPUQuerySetDescriptor, type);
  putchar(',');
  FIELD(WGPUQuerySetDescriptor, count);
  puts("}}");
  puts("}");

  return 0;
}
