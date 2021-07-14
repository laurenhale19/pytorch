#include <ATen/Tensor.h>
#import <ATen/native/metal/MetalCommandBuffer.h>
#import <ATen/native/metal/MetalTensorImpl.h>
#import <ATen/native/metal/MetalTensorImplStorage.h>
#import <ATen/native/metal/MetalTensorUtils.h>
#import <ATen/native/metal/mpscnn/MPSCNNClampOp.h>
#import <ATen/native/metal/mpscnn/MPSImage+Tensor.h>
#import <ATen/native/metal/mpscnn/MPSImageUtils.h>
#include <torch/library.h>

namespace at {
namespace native {
namespace metal {

Tensor& hardtanh_(Tensor& input, const Scalar& min_val, const Scalar& max_val) {
  TORCH_CHECK(input.is_metal());
  MPSImage* X = imageFromTensor(input);
  MetalCommandBuffer* commandBuffer = getCommandBuffer(input);
  MPSImage* Y = createTemporaryImage(commandBuffer, input.sizes().vec());
  float min = min_val.toFloat();
  float max = max_val.toFloat();
  MPSCNNClampOp* clampOp = [MPSCNNClampOp newWithTextures:@[ X, Y ]
                                                     Args:@[ @(min), @(max) ]];
  [clampOp encode:commandBuffer.buffer];
  using MetalTensorImpl = at::MetalTensorImpl<MetalTensorImplStorage>;
  MetalTensorImpl* impl = (MetalTensorImpl*)input.unsafeGetTensorImpl();
  MetalTensorImplStorage& implStorage = impl->unsafe_opaque_handle();
  implStorage.texture()->setImage(Y);
  return input;
}

Tensor hardtanh(
    const Tensor& input,
    const Scalar& min_val,
    const Scalar& max_val) {
  TORCH_CHECK(input.is_metal());
  IntArrayRef outputSize = input.sizes();
  if (input.numel() == 0) {
    return makeTensor({outputSize.vec()}, input.options());
  }
  MetalTensorImplStorage mt{outputSize.vec()};
  MetalCommandBuffer* commandBuffer = getCommandBuffer(input);
  mt.texture()->allocateTemporaryStorage(outputSize, commandBuffer);
  MPSImage* Y = mt.texture()->image();
  float min = min_val.toFloat();
  float max = max_val.toFloat();
  MPSImage* X = imageFromTensor(input);
  MPSCNNClampOp* clampOp = [MPSCNNClampOp newWithTextures:@[ X, Y ]
                                                     Args:@[ @(min), @(max) ]];
  [clampOp encode:commandBuffer.buffer];
  auto output = makeTensor(std::move(mt), input.options());
  return output;
}

at::Tensor clamp(
    const at::Tensor& input,
    const c10::optional<at::Scalar>& min,
    const c10::optional<at::Scalar>& max) {
  TORCH_CHECK(min.has_value() && max.has_value());
  return hardtanh(input, min.value(), max.value());
}

TORCH_LIBRARY_IMPL(aten, Metal, m) {
  m.impl("hardtanh_", TORCH_FN(hardtanh_));
  m.impl("hardtanh", TORCH_FN(hardtanh));
  m.impl("clamp", TORCH_FN(clamp));
};

}
}
}
