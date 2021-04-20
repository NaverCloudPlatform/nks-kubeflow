#!/bin/bash


ROOT_DIR=/Users/jdw/Documents/prj/lab/kubeflow/k8s-yaml/example/kfserving/sklearn

cd $ROOT_DIR

kubectl apply -f $ROOT_DIR/sklearn.yaml -n kfadm

SERVICE_HOSTNAME=$(kubectl get -n admin inferenceservice ${MODEL_NAME} -o jsonpath='{.status.url}' | cut -d "/" -f 3)
INGRESS_HOST=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
INGRESS_PORT=80

# istio-dex version 
#curl -v -H "Host: ${SERVICE_HOSTNAME}" -H "Cookie: authservice_session=${SESSION}" http://${INGRESS_HOST}:${INGRESS_PORT}/v1/models/sklearn-iris:predict -d @./iris-input.json
curl -v -H "Host: ${SERVICE_HOSTNAME}" http://${INGRESS_HOST}:${INGRESS_PORT}/v1/models/sklearn-iris:predict -d @./iris-input.json
