import torch
import time

print('PyTorch version:', torch.__version__)
print('CUDA available:', torch.cuda.is_available())
print('CUDA version:', torch.version.cuda)
print('GPU device:', torch.cuda.get_device_name(0))
print('')

size = 3000
print(f'Creating {size}x{size} matrices on GPU...')
a = torch.randn(size, size, device='cuda')
b = torch.randn(size, size, device='cuda')

c = torch.matmul(a, b)
torch.cuda.synchronize()

print('Running matrix multiplication benchmark...')
start = time.time()
for i in range(20):
    c = torch.matmul(a, b)
torch.cuda.synchronize()
elapsed = time.time() - start

print('')
print('=== Results ===')
print(f'Matrix size: {size}x{size}')
print(f'Operations: 20 matrix multiplications')
print(f'Total time: {elapsed:.2f} seconds')
print(f'TFLOPS: {(2 * size**3 * 20) / elapsed / 1e12:.2f}')
print('')
print('GPU computation completed successfully!')
