# Model attribution

VoiceInput uses the Parakeet TDT 0.6B v3 speech-recognition model created by
NVIDIA and the CoreML conversion published by FluidInference:

- Upstream model: https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3
- CoreML conversion: https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v3-coreml
- License: Creative Commons Attribution 4.0 International (CC BY 4.0)
  https://creativecommons.org/licenses/by/4.0/

The CoreML files are downloaded at runtime and are not redistributed in the
VoiceInput application bundle. VoiceInput does not modify the downloaded model.
The CoreML conversion and quantization were performed by FluidInference.
