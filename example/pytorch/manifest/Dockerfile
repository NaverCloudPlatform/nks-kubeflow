FROM python:3.6-slim

RUN pip install torch===1.2.0 torchvision===0.4.0 -f https://download.pytorch.org/whl/torch_stable.html --trusted-host download.pytorch.org

RUN mkdir -p /app
ADD cifar10.py /app/