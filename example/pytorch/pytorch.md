## 테스트 Flow
1. Local 환경에서 Pytorch 모델을 개발한다. (모델, 학습, 저장 경로 등 정의)
2. Kubeflow Fairing을 사용해서 원격 Cluster(NKS)에 모델을 학습하는 Job 생성
3. 학습 완료된 Pytorch 모델을 KFServing에서 제공하는 Pytorch 서버를 사용해서 배포

## 테스트 환경
- Kubeflow가 설치된 민간 VPC NKS (version : 1.17.11)

## 사전 확인
- 환경
  - python > 3.6
  - python 개발 환경에 kubeflow-fairing 설치
  - docker

- 확인
  - Local -> Docker Registry 접근 확인
  - Cluster <- Docker Registry 접근 환인
  - Local -> Cluster 접근 확인 (kubectl)

- Cluster
  - Namespace를 만들어서 내부에서 작업하는 경우 KFServing에서 모델을 배포할 수 있도록 serving.kubeflow.org/inferenceservice=enabled label 설정
  ```
  kubectl label namespace ${my_namespace} serving.kubeflow.org/inferenceservice=enabled
  ```
  - 모델을 저장할 volume 생성
    - 테스트에서는 NAS가 연결된 pv와 bound된 pvc 생성
    - pvc_name : 'kfserving-models-pvc'

## 1. Local 환경에서 Pytorch 모델 개발

### 모델 코드 작성

- cifar 10 이미지 분류

- --modle-path로 저장 경로 받음
- Pytorch 1.6 버전 기준으로 Model을 저장하는 형태가 변경되어서, 1.6 이하에서는 Model을 Save하는 부분에 **_use_new_zipfile_serialization=False** 를 명시하지 않으면 Inferencing 단계에서 에러가 발생

**pytorch_cifar10.py**
```
import argparse
import os
import shutil

import torch
import torch.nn as nn
import torch.nn.functional as F
import torch.optim as optim
import torchvision
import torchvision.transforms as transforms


class Net(nn.Module):
    def __init__(self):
        super(Net, self).__init__()
        self.conv1 = nn.Conv2d(3, 6, 5)
        self.pool = nn.MaxPool2d(2, 2)
        self.conv2 = nn.Conv2d(6, 16, 5)
        self.fc1 = nn.Linear(16 * 5 * 5, 120)
        self.fc2 = nn.Linear(120, 84)
        self.fc3 = nn.Linear(84, 10)

    def forward(self, x):
        x = self.pool(F.relu(self.conv1(x)))
        x = self.pool(F.relu(self.conv2(x)))
        x = x.view(-1, 16 * 5 * 5)
        x = F.relu(self.fc1(x))
        x = F.relu(self.fc2(x))
        x = self.fc3(x)
        return x


if __name__ == "__main__":

    parser = argparse.ArgumentParser()
    parser.add_argument('--model_path', default='/mnt/pv/models/pytorch/iris', type=str)
    args = parser.parse_args()

    model_path = args.model_path
    if not (os.path.isdir(model_path)):
        os.makedirs(model_path)

    model_file = os.path.join(model_path, 'model.pt')

    transform = transforms.Compose(
        [transforms.ToTensor(),
         transforms.Normalize((0.5, 0.5, 0.5), (0.5, 0.5, 0.5))])

    trainset = torchvision.datasets.CIFAR10(root='./data', train=True,
                                            download=True, transform=transform)
    trainloader = torch.utils.data.DataLoader(trainset, batch_size=4,
                                              shuffle=True, num_workers=2)

    testset = torchvision.datasets.CIFAR10(root='./data', train=False,
                                           download=True, transform=transform)
    testloader = torch.utils.data.DataLoader(testset, batch_size=4,
                                             shuffle=False, num_workers=2)

    classes = ('plane', 'car', 'bird', 'cat',
               'deer', 'dog', 'frog', 'horse', 'ship', 'truck')

    net = Net()
    if torch.cuda.is_available():
        print('Use GPU')
        net = net.cuda()

    criterion = nn.CrossEntropyLoss()
    optimizer = optim.SGD(net.parameters(), lr=0.001, momentum=0.9)

    for epoch in range(2):  # loop over the dataset multiple times

        running_loss = 0.0
        for i, data in enumerate(trainloader, 0):
            # get the inputs; data is a list of [inputs, labels]
            inputs, labels = data

            # zero the parameter gradients
            optimizer.zero_grad()

            # forward + backward + optimize
            outputs = net(inputs)
            loss = criterion(outputs, labels)
            loss.backward()
            optimizer.step()

            # print statistics
            running_loss += loss.item()
            if i % 2000 == 1999:  # print every 2000 mini-batches
                print('[%d, %5d] loss: %.3f' %
                      (epoch + 1, i + 1, running_loss / 2000))
                running_loss = 0.0

    print('Finished Training')

    # Save model
    torch.save(net.state_dict(), model_file, _use_new_zipfile_serialization=False)

    shutil.copy(os.path.abspath(__file__), os.path.join(model_path, __file__))
```


### 컨테이너 이미지 생성

**Dockerfile**
```
FROM python:3.6-slim

RUN pip install torch torchvision

RUN mkdir -p /app
ADD pytorch_cifar10.py /app/
```

## 2. kubeflow fairing을 사용해서 원격 cluster에 모델을 학습하고 저장하는 job 생성

### fairing 코드 작성 및 실행
- 컨테이너 이미지를 빌드하고 컨테이너 이미지 레지스트리에 푸시한 후 job을 생성
- 모델을 저장할 pvc 마운트
- Container Registry : eunbin-test.kr.ncr.ntruss.com
- namespace : eunbin
- pvc name : kfserving-models-pvc

**fairing-local-docker.py**

```
import uuid
from kubeflow import fairing
from kubeflow.fairing.kubernetes import utils as k8s_utils

CONTAINER_REGISTRY = 'eunbin-test.kr.ncr.ntruss.com'

namespace = 'eunbin'
job_name = f'sklean-iris-job-{uuid.uuid4().hex[:4]}'

command=["python", "pytorch_cifar10.py", "--model_path", "/mnt/pv/models/pytorch/cifar10"]
output_map = {
    "Dockerfile": "Dockerfile",
    "pytorch_cifar10.py": "pytorch_cifar10.py"
}

fairing.config.set_preprocessor('python', command=command, path_prefix="/app", output_map=output_map)

fairing.config.set_builder('docker', registry=CONTAINER_REGISTRY, image_name="pytorch-cifar10", dockerfile_path="Dockerfile")

fairing.config.set_deployer('job', namespace=namespace, job_name=job_name,
                            pod_spec_mutators=[k8s_utils.volume_mounts('pvc','kfserving-models-pvc',mount_path='/mnt/pv')],
                            cleanup=False, stream_log=True)

fairing.config.run()
```

## 3. 학습 완료된 Pytorch 모델을 KFServing에서 제공하는 Pytorch 서버를 사용해서 배포
### InferenceService 생성
- storageUri : "${volume type}://${fairing에서 연결해준 volume 이름}/${ 모델이 위치한 경로}
```
storageUri: "pvc://kfserving-models-pvc/models/pytorch/cifar10/"
```

**inferenceservice.yaml**
```
apiVersion: "serving.kubeflow.org/v1alpha2"
kind: "InferenceService"
metadata:
name: "pytorch-cifar10"
spec:
default:
predictor:
pytorch:
storageUri: "pvc://kfserving-models-pvc/models/pytorch/cifar10/"
modelClassName: "Net"
```
- 생성
```
kubectl -n eunbin apply -f inferenceservice.yaml
```

### 예측 실행
- 예측 데이터 : [cifar10-input.json](./cifar10-input.json)
- 요청
```
MODEL_NAME=pytorch-cifar10
SERVICE_HOSTNAME=$(kubectl -n eunbin get inferenceservice pytorch-cifar10 -o jsonpath='{.status.url}' | cut -d "/" -f 3)
INGRESS_HOST=`kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'`
INPUT_PATH=@./cifar10-input.json

curl -v -H "Host: ${SERVICE_HOSTNAME}" http://$INGRESS_HOST/v1/models/$MODEL_NAME:predict -d $INPUT_PATH
```

- 응답

```
*   Trying 110.165.22.81...
* TCP_NODELAY set
* Connected to istio-syste-istio-ingres-77571-5722600-5257d56e84dc.kr.lb.naverncp.com (110.165.22.81) port 80 (#0)
> POST /v1/models/pytorch-cifar10:predict HTTP/1.1
> Host: pytorch-cifar10.eunbin.example.com
> User-Agent: curl/7.58.0
> Accept: */*
> Content-Length: 110681
> Content-Type: application/x-www-form-urlencoded
> Expect: 100-continue
>
< HTTP/1.1 100 Continue
* We are completely uploaded and fine
< HTTP/1.1 200 OK
< content-length: 224
< content-type: application/json; charset=UTF-8
< date: Fri, 22 Jan 2021 01:59:14 GMT
< server: istio-envoy
< x-envoy-upstream-service-time: 61
<
* Connection #0 to host istio-syste-istio-ingres-77571-5722600-5257d56e84dc.kr.lb.naverncp.com left intact
{"predictions": [[-1.7866305112838745, -2.8703629970550537, 0.0788298100233078, 3.68782377243042, -0.6126896142959595, 2.1059298515319824, 0.8862876892089844, -0.5776749849319458, -0.22094634175300598, -1.7740964889526367]]}
```