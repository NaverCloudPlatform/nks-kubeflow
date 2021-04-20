## 테스트 Flow
1. Local 환경에서 Tensorflow MNIST 모델 개발 (모델, 학습 등 정의)
2. Kubeflow Fairing을 사용해서 원격 Cluster(NKS)에 모델을 학습하고 저장하는 Job 생성
3. 학습 완료된 Pytorch 모델을 Seldon에 사전 패키지 된 TensorFlow 서버를 사용해서 배포

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
  - **KFServing과 다르게, Namespace serving.kubeflow.org/inferenceservice=enabled label이 붙어 있으면 안됨(SeldonDeployment 생성 이후 label 생성)**
  - 모델을 저장할 volume 생성
    - 테스트에서는 NAS가 연결된 pv와 bound된 pvc 생성
    - pvc_name : 'seldon-models-pvc'

## 1. Local 환경에서 Tensorflow MNIST 모델을 개발

### 모델 코드 작성

- mnist
- --model_path로 모델 저장 경로 받음
- **pvc를 사용하는 경우, model이 export/{model version} 형태가 아니면 경로를 제대로 찾지 못해서, 이후 seldondeployment init container에서 에러 발생 [관련링크](https://github.com/SeldonIO/seldon-core/issues/1106)**


**tensorflow_mnist.py**
```
from __future__ import absolute_import, division, print_function, unicode_literals
import argparse
import os
import tensorflow as tf

def train():
    print("TensorFlow version: ", tf.__version__)
    parser = argparse.ArgumentParser()
    parser.add_argument('--model_path', default='/mnt/pv/export', type=str)
    args = parser.parse_args()
    version = 1
    export_path = os.path.join(args.model_path, str(version))
    (x_train, y_train), (x_test, y_test) = tf.keras.datasets.mnist.load_data()
    x_train, x_test = x_train / 255.0, x_test / 255.0
    model = tf.keras.models.Sequential([
        tf.keras.layers.Flatten(input_shape=(28, 28)),
        tf.keras.layers.Dense(128, activation='relu'),
        tf.keras.layers.Dropout(0.2),
        tf.keras.layers.Dense(10, activation='softmax')
    ])
    model.compile(optimizer=tf.keras.optimizers.SGD(learning_rate=0.01),
                  loss='sparse_categorical_crossentropy',
                  metrics=['accuracy'])
    print("Training...")
    training_history = model.fit(x_train, y_train, batch_size=64, epochs=10,
                                 validation_split=0.2)
    print('\nEvaluate on test data')
    print('y_test')
    print(y_test)
    results = model.evaluate(x_test, y_test, batch_size=128)
    print('test loss, test acc:', results)
    model.save(export_path)
    print('"Saved model to {}'.format(export_path))
if __name__ == '__main__':
    train()
```

### 컨테이너 이미지
**Dockerfile**
```
FROM tensorflow/tensorflow:2.1.0-py3

RUN mkdir -p /app
ADD tensorflow_mnist.py /app/
```

## 2. Kubeflow Fairing을 사용해서 원격 Cluster(NKS)에서 모델을 학습하는 Job 생성
- 컨테이너 이미지를 빌드하고, 컨테이너 이미지 레지스트리에 푸시한 다음, 쿠버네티스 잡 생성
- container Registery = eunbin-test.kr.ncr.ntruss.com
- namespace : eunbin
- pvc name : seldon-models-pvc


**fairing-local-docker.py**

```
import uuid
from kubeflow import fairing
from kubeflow.fairing.kubernetes import utils as k8s_utils

CONTAINER_REGISTRY = 'eunbin-test.kr.ncr.ntruss.com'
namespace = 'eunbin'
job_name = f'tensorflow-mnist-job-{uuid.uuid4().hex[:4]}'
command = ["python", "tensorflow_mnist.py", "--model_path", "/mnt/pv/export"]
output_map = {
    "Dockerfile": "Dockerfile",
    "tensorflow_mnist.py": "tensorflow_mnist.py"
}
fairing.config.set_preprocessor('python', command=command, path_prefix="/app", output_map=output_map)
fairing.config.set_builder('docker', registry=CONTAINER_REGISTRY, image_name="tensorflow-mnist",
                           dockerfile_path="Dockerfile")
fairing.config.set_deployer('job', namespace=namespace, job_name=job_name,
                            pod_spec_mutators=[
                                k8s_utils.mounting_pvc(pvc_name='seldon-models-pvc', pvc_mount_path='/mnt/pv')],
                            cleanup=False, stream_log=True)
fairing.config.run()
```

## 3. 학습 완료된 Pytorch 모델을 Seldon에 사전 패키지 된 TensorFlow 서버를 사용해서 배포 (순서 중요)

### SeldonDeployment 생성

**seldondeploymnet.yaml**
```
apiVersion: machinelearning.seldon.io/v1alpha2
kind: SeldonDeployment
metadata:
  name: tensorflow-mnist
  namespace: eunbin
spec:
  name: mnist
  predictors:
  - graph:
      children: []
      implementation: TENSORFLOW_SERVER
      modelUri: "pvc://seldon-models-pvc/export"
      name: mnist-model
      parameters:
        - name: signature_name
          type: STRING
          value: serving_default
        - name: model_name
          type: STRING
          value: mnist-model
    name: default
    replicas: 1
```
- 생성
```
kubectl -n eunbin apply -f seldondeploymnet.yaml
```

### label 추가
```
kubectl label namespace eunbin serving.kubeflow.org/inferenceservice=enable
```

### Istio IngressGateway 접근
- seldon core는 트래픽을 전달하기 위해 Istio 사용
- 추론 서버를 배포할 네임스페이스에 Istio와의 연결 통로 역할을 할 게이트웨이 생성

```
INGRESS_HOST=`kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'`

	cat <<EOF | kubectl apply -n $target_ns -f -
apiVersion: networking.istio.io/v1alpha3
kind: Gateway
metadata:
  name: kubeflow-gateway
spec:
  selector:
    istio: ingressgateway
  servers:
  - hosts:
    - '$INGRESS_HOST'
    port:
      name: http
      number: 80
      protocol: HTTP
EOF
```

### 확인
- 조회
```
kubectl -n eunbin get sdep tensorflow-mnist -o yaml
```

- 결과
  - status가 Available 한지 확인

### 에측 요청
- 요청 데이터 : [mnist-input.json](./mnist-input.json)
```
MODELNAME=tensorflow-mnist
NAMESPACE=eunbin
INPUT_PATH=@./mnist-input.json

curl -v -H "Content-Type: application/json" http://$INGRESS_HOST/seldon/$NAMESPACE/$MODELNAME/api/v1.0/predictions -d $INPUT_PATH

```

- 응답
```
*   Trying 110.165.22.81...
* TCP_NODELAY set
* Connected to istio-syste-istio-ingres-77571-5722600-5257d56e84dc.kr.lb.naverncp.com (110.165.22.81) port 80 (#0)
> POST /seldon/eunbin/tensorflow-mnist/api/v1.0/predictions HTTP/1.1
> Host: istio-syste-istio-ingres-77571-5722600-5257d56e84dc.kr.lb.naverncp.com
> User-Agent: curl/7.58.0
> Accept: */*
> Content-Type: application/json
> Content-Length: 5693
> Expect: 100-continue
>
< HTTP/1.1 100 Continue
* We are completely uploaded and fine
< HTTP/1.1 200 OK
< access-control-allow-headers: Accept, Accept-Encoding, Authorization, Content-Length, Content-Type, X-CSRF-Token
< access-control-allow-methods: OPTIONS,POST
< access-control-allow-origin: *
< content-type: application/json
< seldon-puid: 1944f528-a75a-44ab-8530-06636546e491
< x-content-type-options: nosniff
< date: Fri, 22 Jan 2021 02:49:52 GMT
< content-length: 272
< x-envoy-upstream-service-time: 14
< server: istio-envoy
<
{"data":{"names":["t:0","t:1","t:2","t:3","t:4","t:5","t:6","t:7","t:8","t:9"],"tensor":{"shape":[1,10],"values":[0.000193631553,2.05520246e-06,0.000422284531,0.0032700859,7.61226374e-06,0.000101751837,6.91016879e-08,0.993679523,9.27696165e-05,0.00223028776]}},"meta":{}}
* Connection #0 to host istio-syste-istio-ingres-77571-5722600-5257d56e84dc.kr.lb.naverncp.com left intact
```