# Usage: python uvdoc-coreml.py <UVDoc clone> <output .mlpackage>
# Converts the UVDoc network (github.com/tanguymagne/UVDoc, MIT) to Core ML; needs torch and coremltools.
# Compile the result into ScannerKit with: xcrun coremlcompiler compile <output .mlpackage> ScannerKit/Sources/ScannerKit/Resources
import sys

import coremltools as ct
import torch

sys.path.insert(0, sys.argv[1])
from model import UVDocnet  # noqa: E402

model = UVDocnet(num_filter=32, kernel_size=5)
model.load_state_dict(torch.load(f'{sys.argv[1]}/model/best_model.pkl', map_location='cpu')['model_state'])
model.eval()


class Grid(torch.nn.Module):
    def __init__(self, model):
        super().__init__()
        self.model = model

    def forward(self, image):
        return self.model(image)[0]


traced = torch.jit.trace(Grid(model), torch.rand(1, 3, 712, 488))
converted = ct.convert(traced, inputs=[ct.TensorType(name='image', shape=(1, 3, 712, 488))], outputs=[ct.TensorType(name='grid')],
                       minimum_deployment_target=ct.target.iOS17, compute_precision=ct.precision.FLOAT16)
converted.save(sys.argv[2])
