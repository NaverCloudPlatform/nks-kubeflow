# Kubeflow for Naver Cloud
## 설치 환경
- Naver Cloud Kubernetes Service
    - 1.18.xx
## 설치 컴포넌트
- istio v1.3.1
- kubeflow v1.1
- knative v0.16.0
- kfserving v0.4.0
## 디렉토리 및 파일 설명
- 디렉토리
    - ncp-kf-resource : kubeflow 1.1
    - istio-1.3.1 : istio 1.3.1
    - kfserving : knative v.0.16.0, kfserving v0.4.0 install yaml
    - test : kubeflow 테스트 관련 리소스 모음.
- 파일
    - [oneshot-installation-kf-to-nks.sh](oneshot-installation-kf-to-nks.sh) kubectl, kfctl 설치후 쉘 스크립트 실행.
    - [test-nkf-install.sh](test-nkf-install.sh) 테스트 관련 스크립트

##
